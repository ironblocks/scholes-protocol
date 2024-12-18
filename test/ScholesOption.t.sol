// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./BaseTest.sol";
import "../src/OrderBookList.sol";
import "../src/ScholesOption.sol";
import "../src/ScholesCollateral.sol";
import "../src/ScholesLiquidator.sol";
import "../src/SpotPriceOracleApprovedList.sol";
import "../src/SpotPriceOracle.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../src/types/TOptionParams.sol";
import "../src/types/TCollateralRequirements.sol";
import "../src/types/TSweepOrderParams.sol";
import "../src/MockERC20.sol";
import "../src/MockTimeOracle.sol";
import "../src/interfaces/ISpotPriceOracle.sol";

contract ScholesOptionTest is BaseTest {
    function testExerciseAndSettle() public {
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        uint256 shortOptionId = options.getOpposite(longOptionId);
        oracleEthUsd.setMockPrice(1700 * 10 ** oracleEthUsd.decimals()); // WETH/USDC = 1700
        vm.warp(options.getExpiration(longOptionId) - 1000); // Not expired

        // Check the option properties
        assertEq(options.isCall(longOptionId), true);
        assertEq(options.isAmerican(longOptionId), false);

        // Fund account 1 with 10000 USDC collateral
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 0 ether);

        // Fund account 2 with 10000 USDC collateral
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 0 ether);

        // No holder before the option is traded
        assertEq(options.numHolders(longOptionId), 0);
        assertEq(options.numHolders(shortOptionId), 0);

        // Make an offer to sell 1 option at 2 USDC
        vm.startPrank(account1, account1);
        uint256 orderId = callDC2000OrderBook.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 1 hours);
        // Holders won't update until the option is taken
        assertEq(options.numHolders(longOptionId), 0);
        assertEq(options.numHolders(shortOptionId), 0);

        // Take the offer to buy 1 option at 2 USDC
        vm.startPrank(account2, account2);
        callDC2000OrderBook.take(orderId, 1 ether, 2 ether);

        // Both accounts hold the option now
        assertEq(options.numHolders(longOptionId), 1);
        assertEq(options.numHolders(shortOptionId), 1);
        assertEq(options.getHolder(shortOptionId, 0), account1);
        assertEq(options.getHolder(longOptionId, 0), account2);

        // Mock price of WETH/USDC to 2100
        oracleEthUsd.setMockPrice(2100 * 10 ** oracleEthUsd.decimals());

        // Option expires
        vm.warp(options.getExpiration(longOptionId) + 1);

        // Set settlement price
        options.setSettlementPrice(longOptionId);
        assertEq(options.getSettlementPrice(longOptionId), 2100 * 10 ** oracleEthUsd.decimals());

        // Exercise long holding
        vm.startPrank(account2, account2);
        assertEq(options.balanceOf(account2, longOptionId), 1 ether);
        {
            uint256 beforeBaseBalance = collaterals.balanceOf(account2, collaterals.getId(longOptionId, true));
            /* uint256 beforeUnderlyingBlance = */
            collaterals.balanceOf(account2, collaterals.getId(longOptionId, false));
            uint256 beforeOptionBalance = options.balanceOf(account2, longOptionId);
            options.exercise(account2, longOptionId, 0, /*all*/ false, new address[](0), new uint256[](0)); // But there is no underlying - it should pay out in base
            uint256 afterBaseBalance = collaterals.balanceOf(account2, collaterals.getId(longOptionId, true));
            /* uint256 afterUnderlyingBlance = */
            collaterals.balanceOf(account2, collaterals.getId(longOptionId, false));
            //        assertEq(afterBalance, beforeBalance + (2100 - 2000) * 10 ** IERC20Metadata(options.getBaseToken(longOptionId)).decimals());
            // console.log("Base balance change:", beforeBaseBalance, afterBaseBalance);
            // console.log("Underlying balance change:", beforeUnderlyingBlance, afterUnderlyingBlance);
            // console.log("Price settlement: %d strike %d:", options.getSettlementPrice(longOptionId), options.getStrike(longOptionId));
            assertEq(
                afterBaseBalance,
                beforeBaseBalance
                    + options.spotPriceOracle(longOptionId).toBaseFromOption(
                        beforeOptionBalance, options.getSettlementPrice(longOptionId) - options.getStrike(longOptionId)
                    )
            );
        }

        // Settle short holding
        vm.startPrank(account1, account1);
        {
            uint256 beforeBalance = collaterals.balanceOf(account1, collaterals.getId(shortOptionId, true));
            options.settle(account1, shortOptionId, false);
            uint256 afterBalance = collaterals.balanceOf(account1, collaterals.getId(shortOptionId, true));
            assertEq(
                afterBalance,
                beforeBalance - (2100 - 2000) * 10 ** IERC20Metadata(options.getBaseToken(shortOptionId)).decimals()
            );
        }
    }
}
