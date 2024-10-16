// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "chainlink/interfaces/AggregatorV3Interface.sol";
import "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import "openzeppelin-contracts/security/Pausable.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "openzeppelin-contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "./interfaces/IScholesOption.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IScholesLiquidator.sol";
import "./interfaces/ISpotPriceOracle.sol";
import "./interfaces/ISpotPriceOracleApprovedList.sol";
import "./interfaces/IOrderBookList.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/ITimeOracle.sol";
import "./types/TSweepOrderParams.sol";

contract ScholesOption is IScholesOption, ERC1155, Pausable, Ownable, ERC1155Supply {
    uint public constant STALE_COLLATERAL_REQUIREMENT_TIMEOUT = 1 minutes;

    IScholesCollateral public collaterals;
    IScholesLiquidator public liquidator;
    ISpotPriceOracleApprovedList public spotPriceOracleApprovedList;
    IOrderBookList public orderBookList;
    ITimeOracle public timeOracle; // Used only for testing - see ITimeOracle.sol and MockTimeOracle.sol
    IERC20Metadata public schToken;
    
    mapping (uint256 => TOptionParams) public options; // id => OptionParams
    mapping (uint256 => TCollateralRequirements) public collateralRequirements; // id => CollateralRequirements

    mapping (uint256 => mapping (address => bool)) exchanges; // id => (address(IOrderBook) => approved)
    constructor() ERC1155("https://scholes.xyz/option.json") {}

    mapping (uint256 => address[]) public holders; // id => holder[]; the first element in the array for each id is a sentinel
    mapping (uint256 => mapping (address => uint256)) public holdersIndex; // id => (address => index-in-holders)

    // For debugging only!!!
    // function printBalances(address holder, uint256 id) public view {
    //     uint256 baseId = collaterals.getId(id, true);
    //     uint256 underlyingId = collaterals.getId(id, false);
    //     console.log("Address", holder);
    //     console.log("Option", balanceOf(holder, id));
    //     console.log("Base", collaterals.balanceOf(holder, baseId));
    //     console.log("Underlying", collaterals.balanceOf(holder, underlyingId));
    // }

    function numHolders(uint256 id) external view returns (uint256) { // excludes sentinel
        if (holders[id].length == 0) return 0; // Just sentinel
        return holders[id].length - 1; // subtracting 1 to account for sentinel
    }

    function getHolder(uint256 id, uint256 index) external view returns (address) { // index starting from 0
        return holders[id][index+1]; // Adding 1 to index to account for sentinel
    }

    function calculateOptionId(IERC20Metadata underlying, IERC20Metadata base, uint256 strike, uint256 expiration, bool _isCall, bool _isAmerican, bool _isLong) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(address(underlying), address(base), strike, expiration, _isCall, _isAmerican, _isLong)));
    }

    function getOpposite(uint256 id) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(address(options[id].underlying), address(options[id].base), options[id].strike, options[id].expiration, options[id].isCall, options[id].isAmerican, !(options[id].isLong))));        
    }

    function getLongOptionId(uint256 id) external view returns (uint256) {
        if (! options[id].isLong) {
            id = getOpposite(id);
            assert(options[id].isLong); // Bug: looking up non-existent option
        }
        return id;
    }

    // Permissionless
    // ToDo: Restrict strike to reduce fracturing. For wrapped foreign options ignore this restriction.
    function createOptionPair(TOptionParams memory longOptionParams) external returns (uint256 longId, uint256 shortId) {
        require(longOptionParams.isLong, "OptionParams not Long");
        longId = calculateOptionId(longOptionParams.underlying, longOptionParams.base, longOptionParams.strike, longOptionParams.expiration, longOptionParams.isCall, longOptionParams.isAmerican, true);
        shortId = calculateOptionId(longOptionParams.underlying, longOptionParams.base, longOptionParams.strike, longOptionParams.expiration, longOptionParams.isCall, longOptionParams.isAmerican, false);
        require(address(getUnderlyingToken(longId)) == address(0), "Option already exists");

        require(address(longOptionParams.underlying) != address(0), "No underlying");
        require(address(longOptionParams.base) != address(0), "No base");
        require(longOptionParams.strike != 0, "No strike");
        require(longOptionParams.expiration != 0, "No expiration");
        require(longOptionParams.expiration >= timeOracle.getTime(), "Expired option");

        options[longId].underlying = longOptionParams.underlying;
        options[longId].base = longOptionParams.base;
        options[longId].strike = longOptionParams.strike;
        options[longId].expiration = longOptionParams.expiration;
        options[longId].isCall = longOptionParams.isCall;
        options[longId].isAmerican = longOptionParams.isAmerican;
        options[longId].isLong = true;
        options[longId].isSingleCollateral = longOptionParams.isSingleCollateral;
        require(address(spotPriceOracle(longId)) != address(0), "No spot price oracle");
        require(address(schTokenSpotOracle(longId)) != address(0), "No SCH spot price oracle");

        options[shortId].underlying = longOptionParams.underlying;
        options[shortId].base = longOptionParams.base;
        options[shortId].strike = longOptionParams.strike;
        options[shortId].expiration = longOptionParams.expiration;
        options[shortId].isCall = longOptionParams.isCall;
        options[shortId].isAmerican = longOptionParams.isAmerican;
        options[shortId].isLong = false;
        options[shortId].isSingleCollateral = longOptionParams.isSingleCollateral;
        collateralRequirements[shortId].entryCollateralRequirement = type(uint256).max; // Cannot trade before collateral requirements are set
        collateralRequirements[shortId].maintenanceCollateralRequirement = type(uint256).max; // Cannot trade before collateral requirements are set
        if (longOptionParams.isSingleCollateral) {
            uint256 cr;
            if (longOptionParams.isCall) 
                cr = spotPriceOracle(longId).toBase(1 ether); // 1 underlying at current price, but this needs to be constantly maintained as the price changes
            else
                cr = spotPriceOracle(longId).toBase(1 ether, longOptionParams.strike); // 1 underlying at strike price base
            collateralRequirements[shortId].entryCollateralRequirement = cr;
            collateralRequirements[shortId].maintenanceCollateralRequirement = cr;
        }
    }

    function setFriendContracts(address _collaterals, address _liquidator, address _spotPriceOracleApprovedList, address _orderBookList, address _timeOracle, address _schToken) external onlyOwner {
        collaterals = IScholesCollateral(_collaterals);
        liquidator = IScholesLiquidator(_liquidator);
        spotPriceOracleApprovedList = ISpotPriceOracleApprovedList(_spotPriceOracleApprovedList);
        orderBookList = IOrderBookList(_orderBookList);
        timeOracle = ITimeOracle(_timeOracle);
        schToken = IERC20Metadata(_schToken);
    }

    function authorizeExchange(uint256 id, address ob) external {
        require(msg.sender == address(orderBookList), "Unauthorized");
        exchanges[id][ob] = true;
        exchanges[getOpposite(id)][ob] = true;
    }

    function isAuthorizedExchange(uint256 id, address exchange) public view returns (bool) {
        return exchanges[id][exchange];
    }

    modifier onlyExchange(uint256 id) {
        require(isAuthorizedExchange(id, msg.sender), "Unauthorized");
        _;
    }

    function isCall(uint256 id) public view returns (bool) {
        return options[id].isCall;
    }

    function isLong(uint256 id) public view returns (bool) {
        return options[id].isLong;
    }

    function isSingleCollateral(uint256 id) public view returns (bool) {
        return options[id].isSingleCollateral;
    }

    function isAmerican(uint256 id) public view returns (bool) {
        return options[id].isAmerican;
    }

    function getStrike(uint256 id) public view returns (uint256) {
        return options[id].strike;
    }

    function getExpiration(uint256 id) public view returns (uint256) {
        return options[id].expiration;
    }

    function getBaseToken(uint256 id) public view returns (IERC20Metadata) {
        return options[id].base;
    }

    function getUnderlyingToken(uint256 id) public view returns (IERC20Metadata) {
        return options[id].underlying;
    }

    function spotPriceOracle(uint256 id) public view returns (ISpotPriceOracle) {
        return spotPriceOracleApprovedList.getOracle(getUnderlyingToken(id),  getBaseToken(id));
    }

    function schTokenSpotOracle(uint256 id) public view returns (ISpotPriceOracle) {
        return spotPriceOracleApprovedList.getOracle(schToken, getBaseToken(id));
    }

    // Permissionless - the reason is that the collateral requirements are set by anyone including some liquidator
    // WARNING: In the current incomplete implementation, the collateral requirements can only set by the owner of the contract.
    //          This shall change as soon as the proving system is implemented.
    function setCollateralRequirements(uint256 id, uint256 entryCollateralRequirement, uint256 maintenanceCollateralRequirement, uint256 timestamp, bytes calldata proof) external {
        // Can be called by anyone, but the proof must be valid
        require(! options[id].isSingleCollateral, "Fixed single collateral.");
        require(0 != id, "No id");
        require(!(options[id].isLong), "Only short options can have collateral requirements");
        require(timeOracle.getTime() >= timestamp, "Future timestamp");
        require(timeOracle.getTime() <= timestamp + STALE_COLLATERAL_REQUIREMENT_TIMEOUT, "Stale collateral requirements");
        // // The proof is a signature of the hash of the id, entryCollateralRequirement, maintenanceCollateralRequirement, timestamp
        // // Calculate the hash
        // bytes32 hash = keccak256(abi.encodePacked(id, entryCollateralRequirement, maintenanceCollateralRequirement, timestamp));
        // // Unpack the proof into the 3 components needed by exrecover: v, r, s
        // require(proof.length == 65, "Invalid proof length");
        // uint8 v;
        // bytes32 r;
        // bytes32 s;
        // assembly {
        //     r := mload(proof)
        //     s := mload(add(proof, 32))
        //     v := byte(0, mload(add(proof, 64)))
        // }
        // // Verify the proof
        // require(ecrecover(hash, v, r, s) == owner(), "Invalid proof");
        // Enter the values
        collateralRequirements[id].entryCollateralRequirement = entryCollateralRequirement; // Collateral requirement to enter 1 short option (expressed in base collateral tokens)
        collateralRequirements[id].maintenanceCollateralRequirement = maintenanceCollateralRequirement; // Collateral requirement to keep 1 short option without risking liquidation (expressed in base collateral tokens)
        collateralRequirements[id].timestamp = timestamp;
    }

    // !!! Dangerous: Never use collateralRequirements[id] directly - always call this function
    function getCollateralRequirementThreshold(uint256 id, bool entry) public view returns (uint256) {
        // !!! Uncomment this: options[id].isSingleCollateral || timeOracle.getTime() <= collateralRequirements[id].timestamp + STALE_COLLATERAL_REQUIREMENT_TIMEOUT, "Stale collateral requirements");
        if (options[id].isSingleCollateral && options[id].isCall) return spotPriceOracle(id).toBase(1 ether); // 1 underlying at current price
        return entry ? collateralRequirements[id].entryCollateralRequirement : collateralRequirements[id].maintenanceCollateralRequirement;
    }

    function isCollateralSufficient(address holder, uint256 id, bool entry) public view returns (bool) {
        require(0 != id, "No id");
        (uint256 requirement, uint256 possession) = collateralRequirement(holder, id, entry);
        return possession >= requirement;
    }

    function collateralRequirement(address holder, uint256 id, bool entry) public view returns (uint256 requirement, uint256 possession) {
        if (address(0) == holder) return (0, 0);
        ISpotPriceOracle oracle = spotPriceOracle(id);
        // Convert all collateral into base currency (token)
        (uint256 baseBalance, uint256 underlyingBalance) = collaterals.balances(holder, id);
        possession = baseBalance + oracle.toBase(underlyingBalance);
        requirement = collateralRequirement(balanceOf(holder, id), id, entry);
    }

    function collateralRequirement(uint256 amount, uint256 id, bool entry) public view returns (uint256 requirement) {
        require(0 != id, "No id");
        requirement = (options[id].isLong) ? 
            0 : // Long options do not need collateral
            amount * getCollateralRequirementThreshold(id, entry) / 1 ether;
    }

    function getSettlementPrice(uint256 id) external view returns (uint256) {
        return options[id].settlementPrice;
    }

    // Permissionless
    // Should be done as soon as possible after expiration
    function setSettlementPrice(uint256 id) external {
        require(timeOracle.getTime() > options[id].expiration, "Too early");
        require(options[id].settlementPrice == 0, "Already done");
        uint256 oppositeId = getOpposite(id);
        assert(options[oppositeId].settlementPrice == 0); // BUG: Inconsistent settlementPrice
        options[id].settlementPrice = options[oppositeId].settlementPrice = spotPriceOracle(id).getPrice();
        emit SettlementPrice(id, options[id].settlementPrice);
        emit SettlementPrice(oppositeId, options[oppositeId].settlementPrice);
    }

    // !!! Problem with exercise settle:
    // - Exercise and settle may happen in any order after expiration, while exercise comes first before expiration with American Options
    // - Burning is OK, but exercise and settle mint collateral assets in any form (base/underlying) in a first-come-first-serve manner
    // - The above minting is in hope that there will be reverse burning by the counterparty, but counterparties may not execute this for a while
    // Solution 1: perform transfers instead of mint/burn
    // Solution 2: stay with mint/burn (keep tab on total supply) and revise the amounts and conversions

    /// @notice amount == 0 means exercise entire holding
    /// @param _holders List of holder addresses to act as counterparties when American Options are settled
    /// @param amounts List of amounts to be settled for each of the above _holders
    /// @notice _holders and amounts are ignored for European Options or American Options that are exercised/settled after expiration
    function exercise(address holder, uint256 id, uint256 amount, bool toUnderlying, address[] memory _holders, uint256[] memory amounts) public {
        require(isAuthorizedExchange(id, msg.sender) || msg.sender == holder, "Unauthorized");
        require(options[id].isAmerican || timeOracle.getTime() > options[id].expiration, "Not elligible");
        require(options[id].isLong, "Writer cannot exercise");
        require(balanceOf(holder, id) >= amount, "Insufficient holding");
        if (amount == 0) amount = balanceOf(holder, id);
        if (options[id].isAmerican && options[id].expiration <= timeOracle.getTime()) {
            ISpotPriceOracle oracle = spotPriceOracle(id);
            uint256 settlementPrice = oracle.getPrice();
            require(options[id].isCall ? settlementPrice >= options[id].strike : settlementPrice <= options[id].strike, "OTM"); // Out of the money - but still has time value
            exercise(holder, id, amount, settlementPrice, toUnderlying); // Exercise long option
            // Settle short named counterparties
            uint256 totalSettled; // = 0
            uint256 shortId = getOpposite(id);
            for (uint256 i = 0; i < _holders.length; i++) {
                require(balanceOf(_holders[i], shortId) >= amounts[i], "Insufficient amount");
                settle(_holders[i], shortId, amounts[i], settlementPrice, toUnderlying); // Settle short conterparty in the same desired currency
                totalSettled += amounts[i];
            }
            require(amount == totalSettled, "Settlement amounts imbalance");
        } else {
            require(options[id].settlementPrice != 0, "No settlement price"); // Expired and settlement price set
            assert(timeOracle.getTime() > options[id].expiration); // BUG: Settlement price set before expiration
            exercise(holder, id, amount, options[id].settlementPrice, toUnderlying);
        }
    }

    // Should only be called by exercise(uint256 id, uint256 amount, bool toUnderlying, address[] memory _holders, uint256[] memory amounts)
    // No checking - already checked in exercise(uint256 id, uint256 amount, bool toUnderlying, address[] memory _holders, uint256[] memory amounts)
    function exercise(address holder, uint256 id, uint256 amount, uint256 settlementPrice, bool toUnderlying) internal {
        assert(msg.sender != address(this)); // BUG: This must be an internal function
        _burn(holder, id, amount); // Burn option - no collateralization issues as it is always a long holding
        ISpotPriceOracle oracle = spotPriceOracle(id);
        if (options[id].isCall) {
            if (options[id].strike >= settlementPrice) return; // Worthless
            uint256 baseAmount = oracle.toBaseFromOption(amount, settlementPrice-options[id].strike);
            if (toUnderlying) {
                collaterals.mintCollateral(holder, collaterals.getId(id, false/*isBase*/), oracle.toSpot(baseAmount, settlementPrice));
            } else {
                collaterals.mintCollateral(holder, collaterals.getId(id, true/*isBase*/), baseAmount);
            }
        } else { // is Put
            if (options[id].strike <= settlementPrice) return; // Worthless
            uint256 baseAmount = oracle.toBaseFromOption(amount, options[id].strike-settlementPrice);
            if (toUnderlying) {
                collaterals.mintCollateral(holder, collaterals.getId(id, false/*isBase*/), oracle.toSpot(baseAmount, settlementPrice));
            } else {
                collaterals.mintCollateral(holder, collaterals.getId(id, true/*isBase*/), baseAmount);
            }
        }
        emit Exercise(id, holder, amount, timeOracle.getTime(), toUnderlying);
    }

    // Should be called by the holder 
    function settle(address holder, uint256 id, bool toUnderlying) external {
        require(isAuthorizedExchange(id, msg.sender) || msg.sender == holder, "Unauthorized");
        require(timeOracle.getTime() > options[id].expiration, "Not expired");
        require(options[id].settlementPrice != 0, "No settlement price");
        require(! options[id].isLong, "Only Writers can settle");
        settle(holder, id, balanceOf(holder, id), options[id].settlementPrice, toUnderlying);
    }

    // Should only be called by settle(id) or exercise(uint256 id, uint256 amount, bool toUnderlying, address[] memory _holders, uint256[] memory amounts)
    // No id checking - already checked in settle(id) or exercise(uint256 id, uint256 amount, bool toUnderlying, address[] memory _holders, uint256[] memory amounts)
    function settle(address holder, uint256 id, uint256 amount, uint256 settlementPrice, bool toUnderlying) internal {
        assert(msg.sender != address(this)); // BUG: This must be an internal function
        emit Settle(id, holder, amount, timeOracle.getTime(), settlementPrice);
        uint256 baseId = collaterals.getId(id, true);
        uint256 underlyingId = collaterals.getId(id, false);
        ISpotPriceOracle oracle = spotPriceOracle(id);
        // We will assume that the holder has enough collateral to settle the option - this is enforced by the liquidator
        _burn(holder, id, amount); // Burn the option
        if (options[id].isCall) {
            if (options[id].strike >= settlementPrice) return; // Worthless
            _burnCollateral(holder, id, oracle.toBaseFromOption(amount, settlementPrice-options[id].strike), settlementPrice, toUnderlying);
        } else { // is Put
            if (options[id].strike <= settlementPrice) return; // Worthless
            _burnCollateral(holder, id, oracle.toBaseFromOption(amount, options[id].strike-settlementPrice), settlementPrice, toUnderlying);
        }
    }

    function _burnCollateral(address holder, uint256 id, uint256 baseAmount, uint256 settlementPrice, bool toUnderlying) internal {
        ISpotPriceOracle oracle = spotPriceOracle(id);
        if (toUnderlying) {
            uint256 underlyingAmount = oracle.toSpot(baseAmount, settlementPrice);
            uint256 underlyingBalance = collaterals.balanceOf(holder, collaterals.getId(id, false/*isBase*/));
            if (underlyingBalance < underlyingAmount) {
                // Burn the rest in base
                collaterals.burnCollateral(holder, collaterals.getId(id, true/*isBase*/), oracle.toBase(underlyingAmount-underlyingBalance, settlementPrice)); // Must have it - this is enforced by the liquidator
                underlyingAmount = underlyingBalance;
            }
            collaterals.burnCollateral(holder, collaterals.getId(id, false/*isBase*/), underlyingAmount);
        } else {
            uint256 baseBalance = collaterals.balanceOf(holder, collaterals.getId(id, true/*isBase*/));
            if (baseBalance < baseAmount) {
                // Burn the rest in underlying
                collaterals.burnCollateral(holder, collaterals.getId(id, false/*isBase*/), oracle.toSpot(baseAmount-baseBalance, settlementPrice)); // Must have it - this is enforced by the liquidator
                baseAmount = baseBalance;
            }
            collaterals.burnCollateral(holder, collaterals.getId(id, true/*isBase*/), baseAmount);
        }
    }

    function proxySafeTransferFrom(address from, address to, uint256 id, uint256 amount) external {
        require(msg.sender == address(liquidator), "Unauthorized");
        _safeTransferFrom(from, to, id, amount, "");
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) public onlyExchange(id)
    {
        _mint(account, id, amount, data);
    }

    function burn(address from, uint256 id, uint256 amount) public onlyExchange(id) {
        _burn(from, id, amount);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _afterTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155)
    {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
        for (uint256 i = 0; i<ids.length; i++) {
            uint256 id = ids[i];

            // Transfer was optimistically completed
            // Now enforce entry collateral requirements
            if (! isLong(id)) { // because Long options do not require collateral
                require(isCollateralSufficient(from, id, /*entry*/false), "Undercollateralized option sender"); // Reducing short position - enforce only maintenance collateralization
                require(isCollateralSufficient(to, id, /*entry*/true), "Undercollateralized option receipient"); // Increasing short position - enforce entry collateralization
            }

            // Maintain holders
            if (from != address(0) && balanceOf(from, id) == 0) {
                // Remove holder
                if (holders[id].length != holdersIndex[id][from]+1) { // Not last in array
                    // Swap with the last element in array
                    holders[id][holdersIndex[id][from]] = holders[id][holders[id].length-1]; // Move holder
                    holdersIndex[id][holders[id][holders[id].length-1]] = holdersIndex[id][from]; // Adjust index
                }
                holders[id].pop();
                holdersIndex[id][from] = 0;
            }
            if (to != address(0) && balanceOf(to, id) == amounts[i]) { // Just created
                if (holders[id].length == 0) holders[id].push(address(0)); // Push sentinel
                // Record new holder
                holdersIndex[id][to] = holders[id].length;
                holders[id].push(to);
            }
        }

    }
}