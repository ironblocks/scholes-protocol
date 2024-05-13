// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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

    // events
    event Take(uint256 indexed id, address indexed maker, address indexed taker, int256 amount, uint256 price, uint256 uniqid);
    event Make(uint256 indexed id, address indexed maker, int256 amount, uint256 price, uint256 expiration, uint256 indexed uniqid);

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

        // SCH token
        IERC20Metadata SCH = IERC20Metadata(address(new MockERC20("SCH", "SCH", 18, 10**6 * 10**18))); // 1M total supply
        console.log("SCH token address: ", address(SCH));

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

        IScholesLiquidator liquidator = new ScholesLiquidator(address(options));
        console.log(
            "ScholesLiquidator deployed: ",
            address(liquidator)
        );
        SCH.transfer(address(liquidator), 100000 * 10**SCH.decimals()); // Fund the backstop stake with 100000 SCH - move this into the tests

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
        
        options.setFriendContracts(address(collaterals), address(liquidator), address(oracleList), address(obList), address(mockTimeOracle), address(SCH));
        collaterals.setFriendContracts();
        liquidator.setFriendContracts();
        // In order for the liquidation backstop to work, the liquidator must be funded with SCH, by staking using liquidator.stSCH().stake()

        // Mock SCH/USDC oracle
        ISpotPriceOracle oracleSchUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd/*Irrelevant-always mock*/), SCH, USDC, false);
        oracleSchUsd.setMockPrice(1 * 10 ** oracleSchUsd.decimals()); // 1 SCH = 1 USDC
        console.log(
            "SCH/USDC SpotPriceOracle based on ETH/USD deployed, but always mocked: ",
            address(oracleSchUsd)
        );
        oracleList.addOracle(oracleSchUsd);
        
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

        // TCollateralRequirements memory colreq;
        // colreq.entryCollateralRequirement = 2 ether / 10; // 0.2
        // colreq.maintenanceCollateralRequirement = 1 ether / 10; // 0.1

        obList.createScholesOptionPair(optEthUsd);

        ob = obList.getOrderBook(0); // The above WETH/USDC option
        console.log("WETH/USDC order book: ", address(ob));
        longOptionId = ob.longOptionId();
        shortOptionId = options.getOpposite(longOptionId);
        console.log("Long Option Id:", longOptionId);
        options.setCollateralRequirements(shortOptionId, 0, 0, options.timeOracle().getTime(), ""); // No collateral requirements (this is dangerous!!!)
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

    /**
     * Sets expectations for the "Make" event to be emitted with specified attributes.
     * Used to verify that the correct "Make" event is emitted during contract interaction.
     */
    function expectNextCallMakeEvent(uint id, address maker, int256 amount, uint256 price, uint256 expiration, uint256 uniqid) private {
        vm.expectEmit(true, true, true, true);
        emit Make(id, maker, amount, price, expiration, uniqid);
    }

    /**
     * Sets expectations for the "Take" event to be emitted with specified attributes.
     * Used to verify that the correct "Take" event is emitted during contract interaction.
     */
    function expectNextCallTakeEvent(uint id, address maker, address taker, int256 amount, uint256 price, uint256 uniqid) private {
        vm.expectEmit(true, true, true, true);
        emit Take(id, maker, taker, amount, price, uniqid);
    }

    /**
     * Asserts the current counts of bids and offers in the OrderBook match the expected values.
     * This function helps ensure the state of the OrderBook is as expected after operations that
     * should alter the counts of bids or offers.
     */
    function assertOrderCounts(uint256 expectedBids, uint256 expectedOffers) private {
        (uint256 numBids, uint256 numOffers) = ob.numOrders();
        assertEq(numBids, expectedBids, "Mismatch in expected number of bids.");
        assertEq(numOffers, expectedOffers, "Mismatch in expected number of offers.");
    }

   /**
    * A helper function to abstract the common logic for testing the "take" functionality.
    * This function sets up an initial order, executes a take operation, and then verifies
    * the state of the order book post-operation. It is designed to be reusable for testing
    * both buying from an offer and selling to a bid by adjusting the sign of the takeAmount.
    *
    * @param takeAmount The amount of the asset to take. Positive values simulate buying from
    * an offer (take order), while negative values simulate selling to a bid.
    */
    function _testTakeHelper(int256 takeAmount) private {
        int256 makeAmount = takeAmount * -1;
        uint256 expectedOrderId = 0;
        uint takeMakePrice = 2 ether;
        uint oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        address maker = account1;
        address taker = account2;
        oracle.setMockPrice(2000 * 10 ** oracle.decimals());
        // order book should be empty at first
        assertOrderCounts(0, 0);
        // prepare and place the make order
        vm.startPrank(maker, maker);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
        /* We need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more. */
        //expectNextCallMakeEvent(expectedOrderId, maker, makeAmount, takeMakePrice, oneHourExpiration);
        uint256 orderId = ob.make(makeAmount, takeMakePrice, oneHourExpiration);
        assertEq(orderId, expectedOrderId);
        // verify the order was placed and appears in the book
        int256 offerAmount;
        uint256 offerPrice;
        uint256 offerExpiration;
        address offerOwner;
        {
        uint256 uniqid; 
        (offerAmount, offerPrice, offerExpiration, offerOwner, uniqid) =
            takeAmount > 0 ? ob.offers(orderId) : ob.bids(orderId);
        }
        assertEq(offerAmount, makeAmount);
        assertEq(offerPrice, takeMakePrice);
        assertEq(offerExpiration, oneHourExpiration);
        assertEq(offerOwner, maker);
        // the order book should be updated with the new offer
        if (takeAmount > 0) assertOrderCounts(0, 1);
        else assertOrderCounts(1, 0);
        // prepare and place the take order
        vm.startPrank(taker, taker);
        collaterals.deposit(longOptionId, 10000 * 10**USDC.decimals(), 10 ether);
         /* We need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more.
            We also need to add price to the take Event.
            In this order: 
            expectedOrderId, maker, taker, takeAmount, price, uniqid
          */
       // expectNextCallTakeEvent(expectedOrderId, maker, taker, takeAmount);
        ob.take(orderId, takeAmount, takeMakePrice);
        // order book should be empty again
        assertOrderCounts(0, 0);
    }

   /**
    * Test the "take" functionality when buying from an offer.
    * This test uses the helper function to simulate a scenario where an account
    * takes an offer by buying from it.
    */
    function testTakeBuyingFromOffer() public {
        int256 takeAmount = 1 ether;
        _testTakeHelper(takeAmount);
    }

   /**
    * Test the "take" functionality when selling to a bid.
    * This test uses the helper function to simulate a scenario where an account
    * takes a bid by selling to it.
    */
    function testTakeSellingToBid() public {
        int256 takeAmount = -1 ether;
        _testTakeHelper(takeAmount);
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
        // Price does not matter: oracle.setMockPrice(3000 * 10 ** oracle.decimals());
        options.setCollateralRequirements(shortOptionId, 0/*entry*/, 500 * 10**USDC.decimals() /*maintenance*/, options.timeOracle().getTime(), "");

        // Check collateralization of account1 - should be underollateralized
        assertFalse(options.isCollateralSufficient(account1, shortOptionId, false));

        // Now account2 liquidates account1's position
        vm.startPrank(account2, account2);
        options.liquidator().liquidate(account1, shortOptionId, IOrderBook(address(0)), new TTakerEntry[](0));
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
    }
}
