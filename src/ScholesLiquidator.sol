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

contract ScholesLiquidator is IScholesLiquidator {
    IScholesOption options;
    IScholesCollateral collaterals;
    ISpotPriceOracleApprovedList spotPriceOracleApprovedList;
    ITimeOracle timeOracle;

    constructor (address _options) {
        options = IScholesOption(_options);
    }

    function setFriendContracts() external {
        collaterals = options.collaterals();
        spotPriceOracleApprovedList = options.spotPriceOracleApprovedList();
        timeOracle = options.timeOracle();
    }

    function estimateLiqudationPenalty(address holder, uint256 id) external view returns (uint256 penalty, uint256 collectable) {
        require(timeOracle.getTime() <= options.getExpiration(id), "Expired option");
        (uint256 requirement, uint256 possession) = options.collateralRequirement(holder, id, false);
        if (possession >= requirement) return(0, 0);
        penalty = (requirement - possession) * options.getLiquidationPenalty(id) / 1 ether; // Expressed in base
        collectable = possession > penalty ? penalty : possession;
    }

    function liquidate(address holder, uint256 id, IOrderBook ob, TTakerEntry[] memory makers) external {
        require(! options.isLong(id), "Cannot liquidate long holding");
        require(timeOracle.getTime() <= options.getExpiration(id), "Expired option");
        (uint256 requirement, uint256 possession) = options.collateralRequirement(holder, id, /*entry=*/false);
        require(possession < requirement, "Not undercollateralized");
        uint256 baseId = collaterals.getId(id, true);
        collaterals.mintCollateral(holder, baseId, /*maintenance*/requirement); // Temporary, to avoid undercollateralization on transfer. Overkill, but who cares! Cheaper on gas to avoid exact calculation
        collaterals.mintCollateral(msg.sender, baseId, /*maintenance*/requirement); // Temporary collateralize the liquidator, so that he can take over the short option position before buying it back on the market (vanishing) 
        // Now holder has enough funds to pay the liquidation penalty and transfer the option (as always the maintenance collateral is enough for this)
        { // Holder pays the penalty to liquidator optimistically
        // Liquidator does not get the premium built into this short position - it should be built into the liquidation penalty (discuss this)!!!
        uint256 penalty = (requirement - possession) * options.getLiquidationPenalty(id) / 1 ether; // Expressed in base
        uint256 baseBalance = collaterals.balanceOf(holder, baseId);
        collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, msg.sender, baseId, penalty>baseBalance?baseBalance:penalty);
        if (penalty<=baseBalance) return; // paid up
        penalty -= baseBalance;
        // convert penalty to Underlying
        ISpotPriceOracle oracle = options.spotPriceOracle(id);
        penalty = oracle.toSpot(penalty);
        uint256 underlyingId = collaterals.getId(id, false);
        uint256 underlyingBalance = collaterals.balanceOf(holder, underlyingId);
        collaterals.proxySafeTransferFrom(/*irrelevant*/id, holder, msg.sender, underlyingId, penalty>underlyingBalance?underlyingBalance:penalty);
        // no need: if (penalty<=underlyingBalance) return; // paid up
        // no need of further calculations which burn gas
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
}