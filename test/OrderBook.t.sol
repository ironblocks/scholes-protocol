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

    /**
     * Test the cancel function on an empty array.
     * Ensures that canceling a bid or offer on an empty order book reverts with an out-of-bounds error.
     */
    function testCancelOutOfBounds() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        uint256 orderId = 0;
        bool isBid = true;
        vm.expectRevert(stdError.indexOOBError);
        ob.cancel(isBid, orderId);
        isBid = false;
        vm.expectRevert(stdError.indexOOBError);
        ob.cancel(isBid, orderId);
    }

    /**
     * Test the cancel function with an unauthorized user.
     * Ensures that canceling a bid or offer by a non-owner reverts with an "Unauthorized" error.
     */
    function testCancelUnauthorized() public {
        address owner = account1;
        address unauthorizedUser = account2;
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        // Add a bid and an offer
        vm.startPrank(owner);
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 bidOrderId = ob.make(1 ether, 1 ether, oneHourExpiration);
        bool isBid = true;
        bool isMine = ob.isMine(isBid, bidOrderId);
        assertEq(isMine, true);
        uint256 offerOrderId = ob.make(-1 ether, 1 ether, oneHourExpiration);
        isBid = false;
        isMine = ob.isMine(isBid, offerOrderId);
        assertEq(isMine, true);
        assertOrderCounts(1, 1);
        vm.startPrank(unauthorizedUser);
        // Try to cancel the bid with an unauthorized user
        isBid = true;
        isMine = ob.isMine(isBid, bidOrderId);
        assertEq(isMine, false);
        vm.expectRevert("Unauthorized");
        ob.cancel(isBid, bidOrderId);
        // Ensure the orders are still present
        assertOrderCounts(1, 1);
        // Try to cancel the offer with an unauthorized user
        isBid = false;
        isMine = ob.isMine(isBid, offerOrderId);
        assertEq(isMine, false);
        vm.expectRevert("Unauthorized");
        ob.cancel(isBid, offerOrderId);
        // Ensure the orders are still present
        assertOrderCounts(1, 1);
    }

    /**
     * Test the cancel function on the last order in the order book.
     * Ensures that canceling the last bid or offer removes it correctly and updates the order counts.
     */
    function testCancelLastOrder() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        int256 makeAmount = 1 ether;
        uint256 makePrice = 1 ether;
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 bidOrderId = ob.make(makeAmount, makePrice, oneHourExpiration);
        assertOrderCounts(1, 0);
        makeAmount = -1 ether;
        uint256 offerOrderId = ob.make(makeAmount, makePrice, oneHourExpiration);
        assertOrderCounts(1, 1);
        bool isBid = true;
        ob.cancel(isBid, bidOrderId);
        assertOrderCounts(0, 1);
        isBid = false;
        ob.cancel(isBid, offerOrderId);
        assertOrderCounts(0, 0);
    }

    /**
     * Test the cancel function when canceling a non-last bid.
     * Ensures that canceling a bid that is not the last one rearranges the order book correctly.
     */
    function testCancelNonLastBid() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        // Add multiple bids
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 bidOrderId1 = ob.make(1 ether, 1 ether, oneHourExpiration);
        uint256 bidOrderId2 = ob.make(2 ether, 2 ether, oneHourExpiration);
        uint256 bidOrderId3 = ob.make(3 ether, 3 ether, oneHourExpiration);
        assertEq(bidOrderId3, 2);
        assertOrderCounts(3, 0);
        // Cancel the second bid
        bool isBid = true;
        ob.cancel(isBid, bidOrderId2);
        assertOrderCounts(2, 0);
        // Check the remaining orders
        (int256 amount1,,,) = ob.status(isBid, bidOrderId1);
        assertEq(amount1, 1 ether);
        // The 3rd order now has the bidOrderId2
        (int256 amount2,,,) = ob.status(isBid, bidOrderId2);
        assertEq(amount2, 3 ether);
    }

    /**
     * Test the cancel function when canceling a non-last offer.
     * Ensures that canceling an offer that is not the last one rearranges the order book correctly.
     */
    function testCancelNonLastOffer() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        // Add multiple offers
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 offerOrderId1 = ob.make(-1 ether, 1 ether, oneHourExpiration);
        uint256 offerOrderId2 = ob.make(-2 ether, 2 ether, oneHourExpiration);
        uint256 offerOrderId3 = ob.make(-3 ether, 3 ether, oneHourExpiration);
        assertEq(offerOrderId3, 2);
        assertOrderCounts(0, 3);
        // Cancel the second offer
        bool isBid = false;
        ob.cancel(isBid, offerOrderId2);
        assertOrderCounts(0, 2);
        // Check the remaining orders
        (int256 amount1,,,) = ob.status(isBid, offerOrderId1);
        assertEq(amount1, -1 ether);
        // The 3rd order now has the offerOrderId2
        (int256 amount2,,,) = ob.status(isBid, offerOrderId2);
        assertEq(amount2, -3 ether);
    }
}
