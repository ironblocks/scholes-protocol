// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/OrderBookList.sol";
import "../src/ScholesOption.sol";
import "../src/ScholesCollateral.sol";
import "../src/SpotPriceOracleApprovedList.sol";
import "../src/SpotPriceOracle.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../src/types/TOptionParams.sol";
import "../src/types/TCollateralRequirements.sol";
import "../src/MockERC20.sol";
import "../src/MockTimeOracle.sol";
import "../src/interfaces/ISpotPriceOracle.sol";

contract TradingTest is Test {
        
    // Test accounts from passphrase in env (not in repo)
    address constant account0 = 0x1FE2BD1249b9dC89F497052630d393657E62d36a;
    address constant account1 = 0xAA1AD0696F3f970eE4619DD646C12600b003b1b5;
    address constant account2 = 0x264F92eac76DA3244EDc7dD89eC3c7AcC719BE2a;
    address constant account3 = 0x4eBBf92803dfb004b543d4DB592D9C32C0a830A9;

    address constant chainlinkEthUsd = 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08; // on Arbitrum Görli
    // address constant chainlinkEthUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // on Arbitrum One Mainnet

    IOrderBook public ob;
    IScholesOption public options;
    IScholesCollateral collaterals;
    uint256 longOptionId;
    uint256 shortOptionId;
    IERC20Metadata USDC;
    IERC20Metadata WETH;
    ISpotPriceOracle oracle;
    ITimeOracle mockTimeOracle;

    function setUp() public {
        console.log("Creator (owner): ", msg.sender);

        // Test USDC token
        USDC = IERC20Metadata(address(new MockERC20("Test USDC", "USDC", 6, 10**6 * 10**6))); // 1M total supply
        console.log("Test USDC address: ", address(USDC));
        USDC.transfer(account1, 100000 * 10**USDC.decimals());
        USDC.transfer(account2, 100000 * 10**USDC.decimals());
        USDC.transfer(account3, 100000 * 10**USDC.decimals());

        // Test WETH token
        WETH = IERC20Metadata(address(new MockERC20("Test WETH", "WETH", 18, 10**3 * 10**18))); // 1M total supply
        console.log("Test WETH address: ", address(WETH));
        WETH.transfer(account1, 100 * 10**WETH.decimals());
        WETH.transfer(account2, 100 * 10**WETH.decimals());
        WETH.transfer(account3, 100 * 10**WETH.decimals());

        options = new ScholesOption();
        console.log(
            "ScholesOption deployed: ",
            address(options)
        );

        collaterals = new ScholesCollateral(address(options));
        console.log(
            "ScholesCollateral deployed: ",
            address(collaterals)
        );

        ISpotPriceOracleApprovedList oracleList = new SpotPriceOracleApprovedList();
        console.log(
            "SpotPriceOracleApprovedList deployed: ",
            address(oracleList)
        );

        IOrderBookList obList = new OrderBookList(options);
        console.log(
            "OrderBookList deployed: ",
            address(obList)
        );

        mockTimeOracle = new MockTimeOracle();
        console.log(
            "MockTimeOracle deployed: ",
            address(mockTimeOracle)
        );
        
        options.setFriendContracts(address(collaterals), address(oracleList), address(obList), address(mockTimeOracle));

        ISpotPriceOracle oracleEthUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd), WETH, USDC, false);
        console.log(
            "WETH/USDC SpotPriceOracle based on ETH/USD deployed: ",
            address(oracleEthUsd)
        );
        oracleList.addOracle(oracleEthUsd);
    
        TOptionParams memory optEthUsd;
        optEthUsd.underlying = WETH;
        optEthUsd.base = USDC;
        optEthUsd.strike = 2000 * 10 ** oracleEthUsd.decimals();
        optEthUsd.expiration = block.timestamp + 30 * 24 * 60 * 60; // 30 days from now
        optEthUsd.isCall = true;
        optEthUsd.isAmerican = false;
        optEthUsd.isLong = true;

        TCollateralRequirements memory colreq;
        colreq.entryCollateralRequirement = 2 ether / 10; // 0.2
        colreq.maintenanceCollateralRequirement = 1 ether / 10; // 0.1
        colreq.liquidationPenalty = 5 ether / 10; // 0.5 = 50%

        obList.createScholesOptionPair(optEthUsd, colreq);

        ob = obList.getOrderBook(0); // The above WETH/USDC option
        console.log("WETH/USDC order book: ", address(ob));
        longOptionId = ob.longOptionId();
        shortOptionId = options.getOpposite(longOptionId);
        console.log("Long Option Id:", longOptionId);
        require(keccak256("WETH") == keccak256(abi.encodePacked(options.getUnderlyingToken(longOptionId).symbol())), "WETH symbol mismatch"); // Check
        require(optEthUsd.expiration == options.getExpiration(longOptionId), "Expiration mismatch"); // Double-check
        oracle = options.spotPriceOracle(longOptionId);

        vm.startPrank(account1, account1);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);

        vm.startPrank(account2, account2);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);
    }

    function testTake() public {
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
        uint256 orderId = ob.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 60 * 60 /* 1 hour */);
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
        ob.take(orderId, 1 ether, 2 ether);
    }

    function testLiquidate() public {
        oracle.setMockPrice(1700 * 10 ** oracle.decimals());

        // Fund account 1 with 400 USDC collateral
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 400 * 10**USDC.decimals(), 0 ether);

        // Fund account 2 with 10000 USDC + 10 ETH collateral
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 0 ether);

        // Make an offer to sell 1 option at 2 USDC
        vm.startPrank(account1, account1);
        uint256 orderId = ob.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 60 * 60 /* 1 hour */);

        // Take the offer to buy 1 option at 2 USDC
        vm.startPrank(account2, account2);
        ob.take(orderId, 1 ether, 2 ether);

        // Check collateralization of account1 - should be OK
        assert(options.isCollateralSufficient(account1, shortOptionId, false));

        // Mock price of WETH/USDC to 3000
        oracle.setMockPrice(3000 * 10 ** oracle.decimals());

        // Check collateralization of account1 - should be underollateralized
        assertFalse(options.isCollateralSufficient(account1, shortOptionId, false));

        // Now account2 liquidates account1's position
        vm.startPrank(account2, account2);
        options.liquidate(account1, shortOptionId);
    }

    function testExerciseAndSettle() public {
        oracle.setMockPrice(1700 * 10 ** oracle.decimals()); // WETH/USDC = 1700
        mockTimeOracle.setMockTime(options.getExpiration(longOptionId) - 1000); // Not expired

        // Fund account 1 with 10000 USDC collateral
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 0 ether);

        // Fund account 2 with 10000 USDC + 10 ETH collateral
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 0 ether);

        // Make an offer to sell 1 option at 2 USDC
        vm.startPrank(account1, account1);
        uint256 orderId = ob.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 60 * 60 /* 1 hour */);

        // Take the offer to buy 1 option at 2 USDC
        vm.startPrank(account2, account2);
        ob.take(orderId, 1 ether, 2 ether);

        // Mock price of WETH/USDC to 2100
        oracle.setMockPrice(2100 * 10 ** oracle.decimals());

        // Option expires
        mockTimeOracle.setMockTime(options.getExpiration(longOptionId) + 1);

        // Set settlement price
        options.setSettlementPrice(longOptionId);
        assertEq(options.getSettlementPrice(longOptionId), 2100 * 10 ** oracle.decimals());

        // Exercise long holding
        vm.startPrank(account2, account2);
        assertEq(options.balanceOf(account2, longOptionId), 1 ether);
        {
        uint256 beforeBaseBalance = collaterals.balanceOf(account2, collaterals.getId(longOptionId, true));
        /* uint256 beforeUnderlyingBlance = */ collaterals.balanceOf(account2, collaterals.getId(longOptionId, false));
        uint256 beforeOptionBalance = options.balanceOf(account2, longOptionId);
        options.exercise(longOptionId, 0/*all*/, false, new address[](0), new uint256[](0)); // But there is no underlying - it should pay out in base
        uint256 afterBaseBalance = collaterals.balanceOf(account2, collaterals.getId(longOptionId, true));
        /* uint256 afterUnderlyingBlance = */ collaterals.balanceOf(account2, collaterals.getId(longOptionId, false));
//        assertEq(afterBalance, beforeBalance + (2100 - 2000) * 10 ** IERC20Metadata(options.getBaseToken(longOptionId)).decimals());
// console.log("Base balance change:", beforeBaseBalance, afterBaseBalance);
// console.log("Underlying balance change:", beforeUnderlyingBlance, afterUnderlyingBlance);
// console.log("Price settlement: %d strike %d:", options.getSettlementPrice(longOptionId), options.getStrike(longOptionId));
        assertEq(afterBaseBalance, beforeBaseBalance + 
            options.spotPriceOracle(longOptionId).toBaseFromOption(
                beforeOptionBalance,
                options.getSettlementPrice(longOptionId) - options.getStrike(longOptionId)));
        }

        // Settle short holding
        vm.startPrank(account1, account1);
        {
        uint256 beforeBalance = collaterals.balanceOf(account1, collaterals.getId(shortOptionId, true));
        options.settle(shortOptionId);
        uint256 afterBalance = collaterals.balanceOf(account1, collaterals.getId(shortOptionId, true));
        assertEq(afterBalance, beforeBalance - (2100 - 2000) * 10 ** IERC20Metadata(options.getBaseToken(shortOptionId)).decimals());
        }
    }

    function testBad() public {
        vm.startPrank(account1, account1);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
        uint256 orderId = ob.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 60 * 60 /* 1 hour */);
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
        ob.take(orderId, 1 ether, 2 ether);
    }
}
