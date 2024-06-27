// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "./interfaces/IScholesOption.sol";
import "./interfaces/IOrderBook.sol";
import "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract OrderBook is IOrderBook, ERC1155Holder {
    uint256 public constant MAKER_FEE = 0; // (0%) Ratio in 18 decimals
    uint256 public constant TAKER_FEE = 3 * 10 ** 15; // (0.3% = 3/1000) Ratio in 18 decimals

    IScholesOption public scholesOptions;
    uint256 public longOptionId;
    address feeCollector;
    uint256 public uniqidNonce = 0;

    constructor (IScholesOption options, uint256 longId, address _feeCollector) {
        scholesOptions = options;
        longOptionId = longId;
        feeCollector = _feeCollector;
    }

    struct TOrderBookItem {
        int256 amount; // > 0 for bids; < 0 for offers
        uint256 price;
        uint256 expiration;
        address owner;
        uint256 uniqid;
    }

    uint256 public constant NIL = type(uint256).max;

    TOrderBookItem[] public bids; // bids[bidId]
    TOrderBookItem[] public offers; // offers[offerId]

    // Can be called by anyone permissionlessly to free up storage.
    // Usually called by OrderBookList.removeOrderBook.
    function destroy() external {
        require(scholesOptions.timeOracle().getTime() > scholesOptions.getExpiration(longOptionId), "Not expired");
        // selfdestruct(payable(msg.sender)); - deprecated
        delete bids;
        delete offers;
    }
    
    function make(int256 amount, uint256 price, uint256 expiration) public returns (uint256 id) {
        return makes(msg.sender, amount, price, expiration);
    }

    function makes(address maker, int256 amount, uint256 price, uint256 expiration) internal returns (uint256 id) {
        require(scholesOptions.timeOracle().getTime() <= scholesOptions.getExpiration(longOptionId), "Expired option");
        require(scholesOptions.timeOracle().getTime() <= expiration, "Expired order");
        require(amount != 0, "No amount");
        if (amount > 0) { // Long
            id = bids.length;
            bids.push(TOrderBookItem(amount, price, expiration, maker, uniqidNonce));
        } else { // Short
            id = offers.length;
            offers.push(TOrderBookItem(amount, price, expiration, maker, uniqidNonce));
        }
   
        emit Make(id, maker, amount, price, expiration, uniqidNonce);
        uniqidNonce++;
    }

    function take(uint256 id, int256 amount, uint256 price) public {
        takes(msg.sender, id, amount, price);
    }

    function takes(address taker, uint256 id, int256 amount, uint256 price) internal {
        require(amount != 0, "No amount");
        require(scholesOptions.timeOracle().getTime() <= scholesOptions.getExpiration(longOptionId), "Expired option");
        if (amount > 0) { // Buying from offer
            require(price == offers[id].price, "Wrong price"); // In case order id changed before call was broadcasted
            require(taker != offers[id].owner, "Self");
            require(scholesOptions.timeOracle().getTime() <= offers[id].expiration, "Expired");
            require(- offers[id].amount >= amount, "Insufficient offer");
            offers[id].amount += amount;
            changePosition(offers[id].owner, taker, amount, offers[id].price); // Collateralization enforced within
            emit Take(id, offers[id].owner, taker, amount, price, offers[id].uniqid);
            if (offers[id].amount == 0) removeOrder(false, id);
            if (TAKER_FEE > 0) { // Save gas (hopefully the compiler will optimize this out)
                transferCollateral(msg.sender, feeCollector, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption((uint256(amount) * TAKER_FEE) / 1 ether, price)); // Pay the fee
            }
            if (MAKER_FEE > 0) { // Save gas (hopefully the compiler will optimize this out)
                transferCollateral(offers[id].owner, feeCollector, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption((uint256(amount) * MAKER_FEE) / 1 ether, price)); // Pay the fee
            }
        } else { // amount < 0 ; Selling to bid
            require(price == bids[id].price, "Wrong price"); // In case order id changed before call was broadcasted
            require(taker != bids[id].owner, "Self");
            require(scholesOptions.timeOracle().getTime() <= bids[id].expiration, "Expired");
            require(bids[id].amount >= -amount, "Insufficient bid");
            bids[id].amount += amount;
            changePosition(bids[id].owner, taker, amount, bids[id].price); // Collateralization enforced within
            emit Take(id, bids[id].owner, taker, amount, price, bids[id].uniqid);
            if (bids[id].amount == 0) removeOrder(true, id);
            if (TAKER_FEE > 0) { // Save gas (hopefully the compiler will optimize this out)
                transferCollateral(msg.sender, feeCollector, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption((uint256(-amount) * TAKER_FEE) / 1 ether, price)); // Pay the fee
            }
            if (MAKER_FEE > 0) { // Save gas (hopefully the compiler will optimize this out)
                transferCollateral(bids[id].owner, feeCollector, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption((uint256(-amount) * MAKER_FEE) / 1 ether, price)); // Pay the fee
            }
        }
    }

    // Execute order by taking from the list makers and making at the end.
    // It is the caller's responsibility to ensure that the make orders for the given order ID exist and the prices match
    // as well as the amounts are sufficient.
    // If forceFunding is true, the taker will be forced to collateralize the order with base collateral
    // directly from the caller's address and regardless of previous collateralization.
    function sweepAndMake(bool forceFunding, TTakerEntry[] memory makers, TMakerEntry memory toMake) external returns (uint256 id) {
        bool isBuy  = makers.length > 0 ? makers[0].amount > 0 : toMake.amount > 0;
        require(isBuy ? toMake.amount >= 0 : toMake.amount <= 0, "Inconsistent order");
        require(isBuy || !forceFunding, "Cannot force funding for sell orders");
        // Take
        if (forceFunding /* && isBuy */) { // Collateralize with base collateral
            // Calculate funding
            uint256 toDeposit = 0;
            for (uint256 index = 0; index < makers.length; index++) {
                toDeposit += scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption(uint256(makers[index].amount) * (1 ether + TAKER_FEE) / 1 ether, makers[index].price);
            }
            toDeposit += scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption(uint256(toMake.amount) * (1 ether + MAKER_FEE) / 1 ether, toMake.price);
            // To avoid separate authorization for each transfer, we deposit base collateral to this contract and then transfer it to the caller
            { // Safe ERC20 transfer - take the deposit from the caller
                // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
                (bool success, bytes memory data) = address(scholesOptions.getBaseToken(longOptionId)).call(abi.encodeWithSelector(0x23b872dd, msg.sender, address(this), toDeposit));
                require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
            }
            scholesOptions.getBaseToken(longOptionId).approve(address(scholesOptions.collaterals()), toDeposit); // Approve the deposit into the collateral contract
            scholesOptions.collaterals().deposit(longOptionId, toDeposit, 0); // Deposit the base collateral into the collateral contract
            scholesOptions.collaterals().safeTransferFrom(address(this), msg.sender, scholesOptions.collaterals().getId(uint256(longOptionId), true), toDeposit, ""); // Transfer the base collateral to the caller
        }
        for (uint256 index = 0; index < makers.length; index++) {
            require(isBuy ? makers[index].amount > 0 : makers[index].amount < 0, "Inconsistent component orders");
            takes(msg.sender, makers[index].id, makers[index].amount, makers[index].price);
        }
        // Make
        if (toMake.amount != 0) {
            id = makes(msg.sender, toMake.amount, toMake.price, toMake.expiration);
        }
    }

    // Sell the list of long options up to the amount specified
    function vanish(address liquidator, TTakerEntry[] memory makers, int256 amount) external {
        // Take
        for (uint256 index = 0; index < makers.length; index++) {
            require(makers[index].amount < 0, "Inconsistent component orders");
            amount += makers[index].amount;
            takes(liquidator, makers[index].id, makers[index].amount, makers[index].price);
        }
        require(amount >= 0, "Vanish oversold");
    }

    function changePosition(address from, address to, int256 amount, uint256 price) internal {
        // Optimistically pay for the option in collateral - this allows the premium received to be used as collateral
        if (amount > 0) transferCollateral(to, from, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption(uint256(amount), price)); // Pay for long option; all options are 18 decimals
        else transferCollateral(from, to, scholesOptions.spotPriceOracle(longOptionId).toBaseFromOption(uint256(-amount), price)); // Get paid for long position; all options are 18 decimals
        // Now transfer the option
        if (amount > 0) transferOption(from, to, uint256(amount)); // Collateralization is enforced by the transfer
        else transferOption(to, from, uint256(-amount)); // Collateralization is enforced by the transfer
    }

    function transferFees(address from, uint256 amount) internal {
        IScholesCollateral collaterals = scholesOptions.collaterals();
        uint256 baseToTransfer = amount;
        uint256 baseAvailable = collaterals.balanceOf(from, collaterals.getId(longOptionId, true));
        uint256 underlyingToTransfer; // = 0
        if (baseAvailable < baseToTransfer) {
            baseToTransfer = baseAvailable;
            // Transfer the rest (unabailable base balance) in underlying
            underlyingToTransfer = scholesOptions.spotPriceOracle(longOptionId).toSpot(amount - baseToTransfer);
            collaterals.proxySafeTransferFrom(longOptionId, from, address(this), collaterals.getId(longOptionId, false), underlyingToTransfer);
        }
        // Pay in base (in full or whatever available)
        collaterals.proxySafeTransferFrom(longOptionId, from, address(this), collaterals.getId(longOptionId, true), baseToTransfer);
        collaterals.withdrawTo(longOptionId, feeCollector, baseToTransfer, underlyingToTransfer);
    }

    function transferCollateral(address from, address to, uint256 amount) internal {
        IScholesCollateral collaterals = scholesOptions.collaterals();
        uint256 baseToTransfer = amount;
        uint256 baseAvailable = collaterals.balanceOf(from, collaterals.getId(longOptionId, true));
        if (baseAvailable < baseToTransfer) {
            baseToTransfer = baseAvailable;
            // Transfer the rest (unabailable base balance) in underlying
            collaterals.proxySafeTransferFrom(longOptionId, from, to, collaterals.getId(longOptionId, false), scholesOptions.spotPriceOracle(longOptionId).toSpot(amount - baseToTransfer));
        }
        // Pay in base (in full or whatever available)
        collaterals.proxySafeTransferFrom(longOptionId, from, to, collaterals.getId(longOptionId, true), baseToTransfer);
    }

    function transferOption(address from, address to, uint256 amount) internal {
        uint256 shortOptionId = scholesOptions.getOpposite(longOptionId);
        {
        uint256 senderLongToBurn = amount;
        uint256 senderShortToMint; // = 0
        uint256 senderLongBalance = scholesOptions.balanceOf(from, longOptionId);
        if (senderLongBalance < amount) {
            senderLongToBurn = senderLongBalance;
            senderShortToMint = amount - senderLongBalance;
        }
        if (senderLongToBurn > 0) scholesOptions.burn(from, longOptionId, senderLongToBurn); // Enforces collateralization (irrelevantly)
        if (senderShortToMint > 0) scholesOptions.mint(from, shortOptionId, senderShortToMint, ""); // Enforces collateralization
        }
        {
        uint256 recipientShortToBurn = amount;
        uint256 recipientLongToMint; // = 0
        uint256 recipientShortBalance = scholesOptions.balanceOf(to, shortOptionId);
        if (recipientShortBalance < amount) {
            recipientShortToBurn = recipientShortBalance;
            recipientLongToMint = amount - recipientShortBalance;
        }
        if (recipientShortToBurn > 0) scholesOptions.burn(to, shortOptionId, recipientShortToBurn); // Enforces collateralization (irrelevantly)
        if (recipientLongToMint > 0) scholesOptions.mint(to, longOptionId, recipientLongToMint, ""); // Enforces collateralization
        }
    }

    function cancel(bool isBid, uint256 id) public {
        require(msg.sender == (isBid ? bids[id].owner : offers[id].owner), "Unauthorized");
        uint256 uniqid = isBid ? bids[id].uniqid : offers[id].uniqid;
        removeOrder(isBid, id);
        emit Cancel(isBid, id, uniqid);
    }

    function removeOrder(bool isBid, uint256 id) internal {
        if (isBid) {
            // no need: delete bids[id];
            if (bids.length != id+1)  { // Switch with the last
                bids[id] = bids[bids.length-1];
                emit ChangeId(isBid, bids.length-1, id, bids[id].uniqid);
            }
            bids.pop();
        } else {
            // no need: delete offers[id];
            if (offers.length != id+1)  { // Switch with the last
                offers[id] = offers[offers.length-1];
                emit ChangeId(isBid, offers.length-1, id, offers[id].uniqid);
            }
            offers.pop();
        }
    }

    function status(bool isBid, uint256 id) external view returns (int256 amount, uint256 price, uint256 expiration, address owner) {
        if (isBid) {
            require(bids.length > id, "Out of bounds");
            return (bids[id].amount, bids[id].price, bids[id].expiration, bids[id].owner);
        } else {
            require(offers.length > id, "Out of bounds");
            return (offers[id].amount, offers[id].price, offers[id].expiration, offers[id].owner);
        }
    }

    function numOrders() external view returns (uint256 numBids, uint256 numOffers) {
        numBids = bids.length;
        numOffers = offers.length;
    }

    function isMine(bool isBid, uint256 id) external view returns (bool) {
        return ((isBid && msg.sender == bids[id].owner) || (!isBid && msg.sender == offers[id].owner));
    }
}