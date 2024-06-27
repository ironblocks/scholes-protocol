// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "chainlink/interfaces/AggregatorV3Interface.sol";
import "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
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
import "./StSCH.sol";

contract ScholesLiquidator is IScholesLiquidator, Ownable, ERC1155Holder {
    IScholesOption options;
    IScholesCollateral collaterals;
    ISpotPriceOracleApprovedList spotPriceOracleApprovedList;
    ITimeOracle timeOracle;
    IERC20Metadata schToken;
    StSCH stSCH;
    address feeCollector;

    uint256 public constant MAX_INSURANCE_PAYOUT = 10 * 10 ** 16; // (10%) Ratio insurance payout amount / total amount in insurance pool in 18 decimals
    uint256 public constant MAX_BACKSTOP_PAYOUT = 10 * 10 ** 16; // (10%) Ratio backstop payout amount / total amount in backstop pool in 18 decimals
    uint256 public constant LIQUIDATION_PENALTY_LIQUIDATOR = 15 * 10 ** 16; // (15%) Ratio liquidation penalty amount / missing collateral in 18 decimals
    uint256 public constant LIQUIDATION_PENALTY_PROTOCOL = 5 * 10 ** 16; // (5%) Ratio liquidation penalty amount / missing collateral in 18 decimals
    uint256 public constant LIQUIDATION_PENALTY_PROTOCOL_TO_INSURANCE = 100 * 10 ** 16; // (100% initially) Ratio liquidation penalty paid to the protocol to go to the insurance fund
    uint256 public constant DUST = 1_000_000_000;

    constructor (address _options) {
        options = IScholesOption(_options);
        feeCollector = tx.origin; // For now
    }

    function setFriendContracts() external onlyOwner {
        collaterals = options.collaterals();
        spotPriceOracleApprovedList = options.spotPriceOracleApprovedList();
        timeOracle = options.timeOracle();
        schToken = options.schToken();
        stSCH = new StSCH("Staked SCH", "stSCH");
    }

    function estimateLiquidationPenalty(address holder, uint256 id) external view returns (uint256 penalty, uint256 collectable) {
        require(timeOracle.getTime() <= options.getExpiration(id), "Expired option");
        (uint256 requirement, uint256 possession) = options.collateralRequirement(holder, id, false);
        if (possession >= requirement) return(0, 0);
        penalty = (requirement - possession) * (LIQUIDATION_PENALTY_LIQUIDATOR + LIQUIDATION_PENALTY_PROTOCOL) / 1 ether; // Expressed in base
        collectable = possession > penalty ? penalty : possession;
    }

    function liquidate(address holder, uint256 id, IOrderBook ob, TTakerEntry[] memory makers) external {
        liquidate(holder, id, ob, makers, /*maxSacrifice=*/0);
    }

    // !!! Change next line to split penalty between liquidator and protocol and pay out the protocol part to the insurance fund
    function liquidate(address holder, uint256 id, IOrderBook ob, TTakerEntry[] memory makers, uint256 maxSacrifice) public {
        require(! options.isLong(id), "Cannot liquidate long holding");
        require(timeOracle.getTime() <= options.getExpiration(id), "Expired option");
        (uint256 requirement, uint256 possession) = options.collateralRequirement(holder, id, /*entry=*/false);
        require(possession < requirement, "Not undercollateralized");
        uint256 baseId = collaterals.getId(id, true);
        uint256 holderBalanceExOptMint = collaterals.balanceOf(holder, baseId);
        collaterals.mintCollateral(holder, baseId, /*maintenance*/requirement); // Temporary, to avoid undercollateralization on transfer. Overkill, but who cares! Cheaper on gas to avoid exact calculation
        collaterals.mintCollateral(msg.sender, baseId, /*maintenance*/requirement); // Temporary collateralize the liquidator, so that he can take over the short option position before buying it back on the market (vanishing) 
        // Now holder has enough funds to pay the liquidation penalty and transfer the option (as always the maintenance collateral is enough for this)
        { // Holder pays the penalty to liquidator optimistically
        // Liquidator does not get the premium built into this short position - it should be built into the liquidation penalty (discuss this)!!!
        uint256 penalty = (requirement - possession) * (LIQUIDATION_PENALTY_LIQUIDATOR) / 1 ether; // Expressed in base
        require(maxSacrifice <= penalty, "Irrational liquidation");
        {
        uint256 baseToPay = penalty>holderBalanceExOptMint ? holderBalanceExOptMint : penalty;
        collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, msg.sender, baseId, baseToPay);
        holderBalanceExOptMint -= baseToPay;
        penalty -= baseToPay;
        }
        if (penalty>0) { // still not paid up
            // convert penalty to Underlying
            ISpotPriceOracle oracle = options.spotPriceOracle(id);
            penalty = oracle.toSpot(penalty);
            uint256 underlyingId = collaterals.getId(id, false);
            uint256 underlyingBalance = collaterals.balanceOf(holder, underlyingId);
            collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, msg.sender, underlyingId, penalty>underlyingBalance ? underlyingBalance : penalty);
            if (penalty > underlyingBalance) {
                // Cover from insurance fund
                uint256 remainder = payInsurance(id, oracle.toBase(penalty - underlyingBalance));
                remainder = payBackstop(id, remainder);
                require (remainder <= maxSacrifice, "Risk exceeded");
            }
        }
        }
        { // Holder pays the penalty to protocol optimistically
        // Liquidator does not get the premium built into this short position - it should be built into the liquidation penalty (discuss this)!!!
        uint256 penalty = (requirement - possession) * (LIQUIDATION_PENALTY_PROTOCOL) / 1 ether; // Expressed in base
        {
        uint256 baseToPay = penalty>holderBalanceExOptMint ? holderBalanceExOptMint : penalty;
        collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, address(this), baseId, baseToPay);
        collaterals.withdrawTo(id, feeCollector, baseToPay, 0);
        holderBalanceExOptMint -= baseToPay;
        penalty -= baseToPay;
        }
        if (penalty>0) { // still not paid up
            // convert penalty to Underlying
            ISpotPriceOracle oracle = options.spotPriceOracle(id);
            penalty = oracle.toSpot(penalty);
            uint256 underlyingId = collaterals.getId(id, false);
            uint256 underlyingBalance = collaterals.balanceOf(holder, underlyingId);
            collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, address(this), underlyingId, penalty>underlyingBalance ? underlyingBalance : penalty);
            collaterals.withdrawTo(id, feeCollector, 0, penalty>underlyingBalance ? underlyingBalance : penalty);
        }
        }
        uint256 amount = options.balanceOf(holder, id);
        options.proxySafeTransferFrom(holder, msg.sender, id, amount); // Collateralization is enforced by the transfer
        collaterals.burnCollateral(holder, baseId, requirement); // Reverse above temporary mint. Reverts if holder balance < previously issued credit optimistically.

        // At this point the liquidator has the penalty and the option.
        if (makers.length > 0) {
            require(ob.longOptionId() == options.getOpposite(id), "Wrong order book");
            ob.vanish(msg.sender, makers, int256(amount));
        }

        collaterals.burnCollateral(msg.sender, baseId, requirement); // Reverse above temporary mint. Reverts if liquidator balance < previously issued credit optimistically.
        emit Liquidate(id, holder, msg.sender);
    }

    function payInsurance(uint256 optionId, uint256 amount) internal returns (uint256 remainder) {
        // Obtain the ERC20 token address of baseId
        IERC20 baseToken = options.getBaseToken(optionId);
        // Here convert insurance pool from other tokens/currencies if needed
        // Calculate the limit of the insurance fund
        uint256 insuranceBalance =  baseToken.balanceOf(address(this));
        uint256 limit = insuranceBalance * MAX_INSURANCE_PAYOUT / 1 ether;
        uint256 payout = amount > limit ? limit : amount;
        // Transfer the amount from the insurance fund to the liquidator up to the limit
        collaterals.deposit(optionId, payout, /*underlyingAmount=*/0);
        // Return the remainder
        return amount - payout;
    }

    function payBackstop(uint256 optionId, uint256 amount) internal returns (uint256 remainder) {
        // Calculate the limit of the backstop fund
        uint256 backstopBalance = schToken.balanceOf(address(this));
        uint256 limit = backstopBalance * MAX_BACKSTOP_PAYOUT / 1 ether;
        uint256 amountSCH = baseToSCH(optionId, amount);
        uint256 payout = amountSCH > limit ? limit : amountSCH;
        // Transfer the amount from the backstop fund to the liquidator up to the limit
        schToken.transfer(msg.sender, payout);
        // Return the remainder
        return amount - schToBase(optionId, payout);
    }

    function baseToSCH(uint256 optionId, uint256 amount) internal view returns (uint256) {
        ISpotPriceOracle oracleSchBase = spotPriceOracleApprovedList.getOracle(schToken, options.getBaseToken(optionId));
        return oracleSchBase.toSpot(amount);
    }

    function schToBase(uint256 optionId, uint256 amount) internal view returns (uint256) {
        ISpotPriceOracle oracleSchBase = spotPriceOracleApprovedList.getOracle(schToken, options.getBaseToken(optionId));
        return oracleSchBase.toBase(amount);
    }

    function stake(uint256 amount) external {
        require(amount > DUST, "Dust stake");
        uint256 stSchAmount = amount;
        uint256 bal = schToken.balanceOf(address(this));
        if (bal > DUST) {
            stSchAmount *= stSCH.totalSupply();
            stSchAmount /= bal;
        }
        schToken.transferFrom(msg.sender, address(this), amount);
        stSCH.mint(msg.sender, stSchAmount);
    }

    function unstake(uint256 amount) external {
        require(amount > DUST, "Dust unstake");
        if (stSCH.totalSupply() < DUST) return;
        uint256 schAmount = (schToken.balanceOf(address(this)) * amount) / stSCH.totalSupply();
        stSCH.burn(msg.sender, amount);
        schToken.transfer(msg.sender, schAmount);
    }
}