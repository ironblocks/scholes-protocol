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
     * Retrieves an order from the order book and converts it to a TOrderBookItem struct.
     *
     * @param isBid Indicates whether to retrieve from bids (true) or offers (false).
     * @param orderId The ID of the order.
     * @return TOrderBookItem The constructed order struct.
     */
    function getOrderBookItem(bool isBid, uint256 orderId) private view returns (OrderBook.TOrderBookItem memory) {
        (int256 amount, uint256 price, uint256 expiration, address owner, uint256 uniqid) =
            isBid ? ob.bids(orderId) : ob.offers(orderId);
        return OrderBook.TOrderBookItem({
            amount: amount,
            price: price,
            expiration: expiration,
            owner: owner,
            uniqid: uniqid
        });
    }

    /**
     * Asserts the parameters of a given order.
     * This function helps ensure the order details match the expected values.
     *
     * @param order The actual order from the order book.
     * @param expectedAmount The expected amount of the order.
     * @param expectedPrice The expected price of the order.
     * @param expectedExpiration The expected expiration of the order.
     * @param expectedOwner The expected owner of the order.
     */
    function assertOrder(
        OrderBook.TOrderBookItem memory order,
        int256 expectedAmount,
        uint256 expectedPrice,
        uint256 expectedExpiration,
        address expectedOwner
    ) private {
        assertEq(order.amount, expectedAmount, "Mismatch in order amount.");
        assertEq(order.price, expectedPrice, "Mismatch in order price.");
        assertEq(order.expiration, expectedExpiration, "Mismatch in order expiration.");
        assertEq(order.owner, expectedOwner, "Mismatch in order owner.");
    }

    /**
     * Asserts the parameters of a given order by retrieving it from the order book.
     * This function helps ensure the order details match the expected values.
     *
     * @param isBid Indicates whether to retrieve from bids (true) or offers (false).
     * @param orderId The ID of the order.
     * @param expectedAmount The expected amount of the order.
     * @param expectedPrice The expected price of the order.
     * @param expectedExpiration The expected expiration of the order.
     * @param expectedOwner The expected owner of the order.
     */
    function assertOrder(
        bool isBid,
        uint256 orderId,
        int256 expectedAmount,
        uint256 expectedPrice,
        uint256 expectedExpiration,
        address expectedOwner
    ) private {
        OrderBook.TOrderBookItem memory order = getOrderBookItem(isBid, orderId);
        assertOrder(order, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
    }

    /**
     * Test the destroy function when the contract is not expired.
     * Ensures that calling destroy before expiration reverts with the message "Not expired".
     */
    function testDestroyNotExpired() public {
        // Try to destroy the order book before expiration
        vm.expectRevert("Not expired");
        ob.destroy();
    }

    /**
     * Test the destroy function when the contract is expired.
     * Ensures that calling destroy after expiration deletes the bids and offers correctly.
     */
    function testDestroyAfterExpiration() public {
        // Set up the order book with initial orders
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        // place a couple of orders
        ob.make(-5 ether, 1 ether, oneHourExpiration);
        ob.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(1, 1);
        // Move time forward to after the expiration of the option
        vm.warp(options.getExpiration(longOptionId) + 1);
        // Destroy the order book
        ob.destroy();
        // Ensure the order book is empty
        assertOrderCounts(0, 0);
        // Destroy can be called multiple times with no issue
        ob.destroy();
        // Ensure the order book remains empty
        assertOrderCounts(0, 0);
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
        bool isBid = takeAmount < 0;
        assertOrder(isBid, orderId, makeAmount, takeMakePrice, oneHourExpiration, maker);
        // the order book should be updated with the new order
        if (isBid) assertOrderCounts(1, 0);
        else assertOrderCounts(0, 1);
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

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles partial order matching.
     * This test sets up initial orders, executes the sweep and make operation, and then verifies
     * the state of the order book to ensure all orders are processed as expected.
     */
    function testSweepAndMake() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        oracle.setMockPrice(2000 * 10 ** oracle.decimals());
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = ob.make(-5 ether, 1 ether, oneHourExpiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = ob.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(1, 1);
        // Prepare the sweep and make to partially take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 1.5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(1 ether, 2 ether, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        bool forceFunding = true;
        uint256 newOrderId = ob.sweepAndMake(forceFunding, makers, toMake);
        // the `toMake` order ID
        assertEq(newOrderId, 1);
        // We have a new bid coming from the `toMake`
        // The rest of the orders are still there since `makers` was only matching partially
        assertOrderCounts(2, 1);
        // Now let's check each order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
        }
        // The new `toMake` order was placed
        {
            bool isBid = true;
            int256 expectedAmount = 1 ether;
            uint256 expectedPrice = 2 ether;
            uint256 expectedExpiration = twoHourExpiration;
            address expectedOwner = account3;
            assertOrder(isBid, newOrderId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
        }
        // The offer was partially matching and its amount got updated
        {
            bool isBid = false;
            int256 expectedAmount = -3.5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account1;
            assertOrder(isBid, offerId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
        }
    }

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles full order matching and no make.
     * This is a regression test for a fix introduced in 1ce1c21, prior the fix the error was:
     * Reason: revert: ERC1155: insufficient balance for transfer
     */
    function testSweepAndMakeNoMake() public {
        // Order book should be empty at first
        assertOrderCounts(0, 0);
        oracle.setMockPrice(2000 * 10 ** oracle.decimals());
        uint256 oneHourExpiration = mockTimeOracle.getTime() + 1 hours;
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = ob.make(-5 ether, 1 ether, oneHourExpiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = ob.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(1, 1);
        // Prepare the sweep and make to fully take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(0, 0, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        bool forceFunding = true;
        uint256 newOrderId = ob.sweepAndMake(forceFunding, makers, toMake);
        // no new order ID since no `toMake`
        assertEq(newOrderId, 0);
        // The offer was fully matched and removed from the order book
        assertOrderCounts(1, 0);
        // Now let's check each order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
        }
    }

    /**
     * Test the `sweepAndMake` function for "Inconsistent component orders" case.
     * This should revert with the message "Inconsistent component orders".
     */
    function testSweepAndMakeInconsistentComponentOrders() public {
        oracle.setMockPrice(2000 * 10 ** oracle.decimals());
        uint256 expiration = mockTimeOracle.getTime() + 1 hours;
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = ob.make(-5 ether, 1 ether, expiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = ob.make(5 ether, 1 ether, expiration);
        // We now have 2 orders on the book
        assertOrderCounts(1, 1);
        // Prepare the sweep and make with inconsistent maker amounts
        TTakerEntry[] memory makers = new TTakerEntry[](2);
        makers[0] = TTakerEntry(offerId, 1.5 ether, 1 ether); // Positive amount
        makers[1] = TTakerEntry(bidId, -1.5 ether, 1 ether); // Negative amount
        // toMake with a valid amount
        TMakerEntry memory toMake = TMakerEntry(1 ether, 2 ether, expiration);
        bool forceFunding = false;
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        // Expect revert with "Inconsistent component orders"
        vm.expectRevert("Inconsistent component orders");
        ob.sweepAndMake(forceFunding, makers, toMake);
    }

    /**
     * Test the `sweepAndMake` function for "Inconsistent order" case when buying with a negative amount.
     * This should revert with the message "Inconsistent order".
     */
    function testSweepAndMakeInconsistentOrderBuy() public {
        uint256 orderId = 0;
        uint256 expiration = mockTimeOracle.getTime() + 1 hours;
        // Prepare the sweep and make to partially take from orderId with inconsistent toMake amount
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(orderId, 1.5 ether, 1 ether);
        // toMake with negative amount for buy order
        TMakerEntry memory toMake = TMakerEntry(-1 ether, 2 ether, expiration);
        bool forceFunding = true;
        // Expect revert with "Inconsistent order"
        vm.expectRevert("Inconsistent order");
        ob.sweepAndMake(forceFunding, makers, toMake);
    }

    /**
     * Test the `sweepAndMake` function for "Inconsistent order" case when selling with a positive amount.
     * This should revert with the message "Inconsistent order".
     */
    function testSweepAndMakeInconsistentOrderSell() public {
        uint256 orderId = 0;
        uint256 expiration = mockTimeOracle.getTime() + 1 hours;
        // Prepare the sweep and make to partially take from orderId with inconsistent toMake amount
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(orderId, -1.5 ether, 1 ether);
        // toMake with positive amount for sell order
        TMakerEntry memory toMake = TMakerEntry(1 ether, 2 ether, expiration);
        bool forceFunding = false; // forceFunding must be false for sell orders
        // Expect revert with "Inconsistent order"
        vm.expectRevert("Inconsistent order");
        ob.sweepAndMake(forceFunding, makers, toMake);
    }

    /**
     * Test the `sweepAndMake` function for "Cannot force funding for sell orders" case.
     * This should revert with the message "Cannot force funding for sell orders".
     */
    function testSweepAndMakeForceFundingInconsistentOrder() public {
        uint256 orderId = 0;
        uint256 expiration = mockTimeOracle.getTime() + 1 hours;
        // Prepare the sweep and make to partially take from orderId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(orderId, -1.5 ether, 1 ether);
        // toMake with negative amount for sell order
        TMakerEntry memory toMake = TMakerEntry(-1 ether, 2 ether, expiration);
        bool forceFunding = true; // forceFunding must be false for sell orders
        // Expect revert with "Cannot force funding for sell orders"
        vm.expectRevert("Cannot force funding for sell orders");
        ob.sweepAndMake(forceFunding, makers, toMake);
    }
}
