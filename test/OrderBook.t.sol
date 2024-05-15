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

contract OrderBookTest is BaseTest {
    // events
    event Take(
        uint256 indexed id, address indexed maker, address indexed taker, int256 amount, uint256 price, uint256 uniqid
    );
    event Make(
        uint256 indexed id,
        address indexed maker,
        int256 amount,
        uint256 price,
        uint256 expiration,
        uint256 indexed uniqid
    );

    function setUp() public {
        setUpBase();
    }

    /**
     * Sets expectations for the "Make" event to be emitted with specified attributes.
     * Used to verify that the correct "Make" event is emitted during contract interaction.
     */
    function expectNextCallMakeEvent(
        uint256 id,
        address maker,
        int256 amount,
        uint256 price,
        uint256 expiration,
        uint256 uniqid
    ) private {
        vm.expectEmit(true, true, true, true);
        emit Make(id, maker, amount, price, expiration, uniqid);
    }

    /**
     * Sets expectations for the "Take" event to be emitted with specified attributes.
     * Used to verify that the correct "Take" event is emitted during contract interaction.
     */
    function expectNextCallTakeEvent(
        uint256 id,
        address maker,
        address taker,
        int256 amount,
        uint256 price,
        uint256 uniqid
    ) private {
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
        uint256 takeMakePrice = 2 ether;
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        address maker = account1;
        address taker = account2;
        oracle.setMockPrice(2000 * 10 ** oracle.decimals());
        // order book should be empty at first
        assertOrderCounts(0, 0);
        // prepare and place the make order
        vm.startPrank(maker, maker);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        // we need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more
        // expectNextCallMakeEvent(expectedOrderId, maker, makeAmount, takeMakePrice, oneHourExpiration);
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
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        // we need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more
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
}
