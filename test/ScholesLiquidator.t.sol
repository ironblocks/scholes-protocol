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

contract ScholesLiquidatorTest is BaseTest {
    function testLiquidate() public {
        oracleEthUsd.setMockPrice(1700 * 10 ** oracleEthUsd.decimals());
        uint256 longOptionId = call2000OrderBook.longOptionId();
        uint256 shortOptionId = options.getOpposite(longOptionId);

        // Fund account 1 with 400 USDC collateral
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 400 * 10 ** USDC.decimals(), 0 ether);

        // Fund account 2 with 10000 USDC + 10 ETH collateral
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 0 ether);

        // Make an offer to sell 1 option at 2 USDC
        vm.startPrank(account1, account1);
        uint256 orderId = call2000OrderBook.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 60 * 60 /* 1 hour */ );

        // Take the offer to buy 1 option at 2 USDC
        vm.startPrank(account2, account2);
        call2000OrderBook.take(orderId, 1 ether, 2 ether);

        // Check collateralization of account1 - should be OK
        assert(options.isCollateralSufficient(account1, shortOptionId, false));

        // Mock price of WETH/USDC to 3000
        // Price does not matter: oracleEthUsd.setMockPrice(3000 * 10 ** oracleEthUsd.decimals());
        options.setCollateralRequirements(
            shortOptionId, 0, /*entry*/ 500 * 10 ** USDC.decimals(), /*maintenance*/ options.timeOracle().getTime(), ""
        );

        // Check collateralization of account1 - should be underollateralized
        assertFalse(options.isCollateralSufficient(account1, shortOptionId, false));

        // Now account2 liquidates account1's position
        vm.startPrank(account2, account2);
        options.liquidator().liquidate(account1, shortOptionId, IOrderBook(address(0)), new TTakerEntry[](0));
    }
}
