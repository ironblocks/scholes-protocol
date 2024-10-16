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
    function assertOrderCounts(IOrderBook orderBook, uint256 expectedBids, uint256 expectedOffers) private {
        (uint256 numBids, uint256 numOffers) = orderBook.numOrders();
        assertEq(numBids, expectedBids, "Mismatch in expected number of bids.");
        assertEq(numOffers, expectedOffers, "Mismatch in expected number of offers.");
    }

    /**
     * Retrieves an order from the order book and converts it to a TOrderBookItem struct.
     *
     * @param orderBook The order book to retrieve the item from.
     * @param isBid Indicates whether to retrieve from bids (true) or offers (false).
     * @param orderId The ID of the order.
     * @return TOrderBookItem The constructed order struct.
     */
    function getOrderBookItem(IOrderBook orderBook, bool isBid, uint256 orderId)
        private
        view
        returns (OrderBook.TOrderBookItem memory)
    {
        (int256 amount, uint256 price, uint256 expiration, address owner, uint256 uniqid) =
            isBid ? orderBook.bids(orderId) : orderBook.offers(orderId);
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
     * @param orderBook The order book to retrieve the item from.
     * @param isBid Indicates whether to retrieve from bids (true) or offers (false).
     * @param orderId The ID of the order.
     * @param expectedAmount The expected amount of the order.
     * @param expectedPrice The expected price of the order.
     * @param expectedExpiration The expected expiration of the order.
     * @param expectedOwner The expected owner of the order.
     */
    function assertOrder(
        IOrderBook orderBook,
        bool isBid,
        uint256 orderId,
        int256 expectedAmount,
        uint256 expectedPrice,
        uint256 expectedExpiration,
        address expectedOwner
    ) private {
        OrderBook.TOrderBookItem memory order = getOrderBookItem(orderBook, isBid, orderId);
        assertOrder(order, expectedAmount, expectedPrice, expectedExpiration, expectedOwner);
    }

    /**
     * Test the destroy function when the contract is not expired.
     * Ensures that calling destroy before expiration reverts with the message "Not expired".
     */
    function testDestroyNotExpired() public {
        // Try to destroy the order book before expiration
        vm.expectRevert("Not expired");
        callDC2000OrderBook.destroy();
    }

    /**
     * Test the destroy function when the contract is expired.
     * Ensures that calling destroy after expiration deletes the bids and offers correctly.
     */
    function testDestroyAfterExpiration() public {
        // Set up the order book with initial orders
        callDC2000OrderBook.make(-5 ether, 1 ether, oneHourExpiration);
        callDC2000OrderBook.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        // Move time forward to after the expiration of the option
        vm.warp(options.getExpiration(callDC2000OrderBook.longOptionId()) + 1);
        // Destroy the order book
        callDC2000OrderBook.destroy();
        // Ensure the order book is empty
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        // Destroy can be called multiple times with no issue
        callDC2000OrderBook.destroy();
        // Ensure the order book remains empty
        assertOrderCounts(callDC2000OrderBook, 0, 0);
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
        address maker = account1;
        address taker = account2;
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        // order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        // prepare and place the make order
        vm.startPrank(maker, maker);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        // we need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more
        // expectNextCallMakeEvent(expectedOrderId, maker, makeAmount, takeMakePrice, oneHourExpiration);
        uint256 orderId = callDC2000OrderBook.make(makeAmount, takeMakePrice, oneHourExpiration);
        assertEq(orderId, expectedOrderId);
        // verify the order was placed and appears in the book
        bool isBid = takeAmount < 0;
        assertOrder(callDC2000OrderBook, isBid, orderId, makeAmount, takeMakePrice, oneHourExpiration, maker);
        // the order book should be updated with the new order
        if (isBid) assertOrderCounts(callDC2000OrderBook, 1, 0);
        else assertOrderCounts(callDC2000OrderBook, 0, 1);
        // prepare and place the take order
        vm.startPrank(taker, taker);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        // we need to add uniqid in the event. Uniqid is a nonce that gets updated with each order, see OrderBook.sol for more
        // expectNextCallTakeEvent(expectedOrderId, maker, taker, takeAmount);
        callDC2000OrderBook.take(orderId, takeAmount, takeMakePrice);
        // order book should be empty again
        assertOrderCounts(callDC2000OrderBook, 0, 0);
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
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        uint256 orderId = 0;
        bool isBid = true;
        vm.expectRevert(stdError.indexOOBError);
        callDC2000OrderBook.cancel(isBid, orderId);
        isBid = false;
        vm.expectRevert(stdError.indexOOBError);
        callDC2000OrderBook.cancel(isBid, orderId);
    }

    /**
     * Test the cancel function with an unauthorized user.
     * Ensures that canceling a bid or offer by a non-owner reverts with an "Unauthorized" error.
     */
    function testCancelUnauthorized() public {
        address owner = account1;
        address unauthorizedUser = account2;
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        // Add a bid and an offer
        vm.startPrank(owner);
        uint256 bidOrderId = callDC2000OrderBook.make(1 ether, 1 ether, oneHourExpiration);
        bool isBid = true;
        bool isMine = callDC2000OrderBook.isMine(isBid, bidOrderId);
        assertEq(isMine, true);
        uint256 offerOrderId = callDC2000OrderBook.make(-1 ether, 1 ether, oneHourExpiration);
        isBid = false;
        isMine = callDC2000OrderBook.isMine(isBid, offerOrderId);
        assertEq(isMine, true);
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        vm.startPrank(unauthorizedUser);
        // Try to cancel the bid with an unauthorized user
        isBid = true;
        isMine = callDC2000OrderBook.isMine(isBid, bidOrderId);
        assertEq(isMine, false);
        vm.expectRevert("Unauthorized");
        callDC2000OrderBook.cancel(isBid, bidOrderId);
        // Ensure the orders are still present
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        // Try to cancel the offer with an unauthorized user
        isBid = false;
        isMine = callDC2000OrderBook.isMine(isBid, offerOrderId);
        assertEq(isMine, false);
        vm.expectRevert("Unauthorized");
        callDC2000OrderBook.cancel(isBid, offerOrderId);
        // Ensure the orders are still present
        assertOrderCounts(callDC2000OrderBook, 1, 1);
    }

    /**
     * Test the cancel function on the last order in the order book.
     * Ensures that canceling the last bid or offer removes it correctly and updates the order counts.
     */
    function testCancelLastOrder() public {
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        int256 makeAmount = 1 ether;
        uint256 makePrice = 1 ether;
        uint256 bidOrderId = callDC2000OrderBook.make(makeAmount, makePrice, oneHourExpiration);
        assertOrderCounts(callDC2000OrderBook, 1, 0);
        makeAmount = -1 ether;
        uint256 offerOrderId = callDC2000OrderBook.make(makeAmount, makePrice, oneHourExpiration);
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        bool isBid = true;
        callDC2000OrderBook.cancel(isBid, bidOrderId);
        assertOrderCounts(callDC2000OrderBook, 0, 1);
        isBid = false;
        callDC2000OrderBook.cancel(isBid, offerOrderId);
        assertOrderCounts(callDC2000OrderBook, 0, 0);
    }

    /**
     * Test the cancel function when canceling a non-last bid.
     * Ensures that canceling a bid that is not the last one rearranges the order book correctly.
     */
    function testCancelNonLastBid() public {
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        // Add multiple bids
        uint256 bidOrderId1 = callDC2000OrderBook.make(1 ether, 1 ether, oneHourExpiration);
        uint256 bidOrderId2 = callDC2000OrderBook.make(2 ether, 2 ether, oneHourExpiration);
        uint256 bidOrderId3 = callDC2000OrderBook.make(3 ether, 3 ether, oneHourExpiration);
        assertEq(bidOrderId3, 2);
        assertOrderCounts(callDC2000OrderBook, 3, 0);
        // Cancel the second bid
        bool isBid = true;
        callDC2000OrderBook.cancel(isBid, bidOrderId2);
        assertOrderCounts(callDC2000OrderBook, 2, 0);
        // Check the remaining orders
        (int256 amount1,,,) = callDC2000OrderBook.status(isBid, bidOrderId1);
        assertEq(amount1, 1 ether);
        // The 3rd order now has the bidOrderId2
        (int256 amount2,,,) = callDC2000OrderBook.status(isBid, bidOrderId2);
        assertEq(amount2, 3 ether);
    }

    /**
     * Test the cancel function when canceling a non-last offer.
     * Ensures that canceling an offer that is not the last one rearranges the order book correctly.
     */
    function testCancelNonLastOffer() public {
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        // Add multiple offers
        uint256 offerOrderId1 = callDC2000OrderBook.make(-1 ether, 1 ether, oneHourExpiration);
        uint256 offerOrderId2 = callDC2000OrderBook.make(-2 ether, 2 ether, oneHourExpiration);
        uint256 offerOrderId3 = callDC2000OrderBook.make(-3 ether, 3 ether, oneHourExpiration);
        assertEq(offerOrderId3, 2);
        assertOrderCounts(callDC2000OrderBook, 0, 3);
        // Cancel the second offer
        bool isBid = false;
        callDC2000OrderBook.cancel(isBid, offerOrderId2);
        assertOrderCounts(callDC2000OrderBook, 0, 2);
        // Check the remaining orders
        (int256 amount1,,,) = callDC2000OrderBook.status(isBid, offerOrderId1);
        assertEq(amount1, -1 ether);
        // The 3rd order now has the offerOrderId2
        (int256 amount2,,,) = callDC2000OrderBook.status(isBid, offerOrderId2);
        assertEq(amount2, -3 ether);
    }

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles partial order matching.
     * This test sets up initial orders, executes the sweep and make operation, and then verifies
     * the state of the order book to ensure all orders are processed as expected.
     */
    function testSweepAndMake() public {
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = callDC2000OrderBook.make(-5 ether, 1 ether, oneHourExpiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = callDC2000OrderBook.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        // Prepare the sweep and make to partially take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 1.5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(1 ether, 2 ether, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        bool forceFunding = true;
        uint256 newOrderId = callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
        // the `toMake` order ID
        assertEq(newOrderId, 1);
        // We have a new bid coming from the `toMake`
        // The rest of the orders are still there since `makers` was only matching partially
        assertOrderCounts(callDC2000OrderBook, 2, 1);
        // Now let's check each order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(
                callDC2000OrderBook, isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
        // The new `toMake` order was placed
        {
            bool isBid = true;
            int256 expectedAmount = 1 ether;
            uint256 expectedPrice = 2 ether;
            uint256 expectedExpiration = twoHourExpiration;
            address expectedOwner = account3;
            assertOrder(
                callDC2000OrderBook, isBid, newOrderId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
        // The offer was partially matching and its amount got updated
        {
            bool isBid = false;
            int256 expectedAmount = -3.5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account1;
            assertOrder(
                callDC2000OrderBook, isBid, offerId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
    }

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles full order matching and no make.
     * This is a regression test for a fix introduced in 1ce1c21, prior the fix the error was:
     * Reason: revert: ERC1155: insufficient balance for transfer
     */
    function testSweepAndMakeNoMake() public {
        // Order book should be empty at first
        assertOrderCounts(callDC2000OrderBook, 0, 0);
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = callDC2000OrderBook.make(-5 ether, 1 ether, oneHourExpiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = callDC2000OrderBook.make(5 ether, 1 ether, oneHourExpiration);
        // We now have 2 orders on the book
        assertOrderCounts(callDC2000OrderBook, 1, 1);
        // Prepare the sweep and make to fully take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(0, 0, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        bool forceFunding = true;
        uint256 newOrderId = callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
        // no new order ID since no `toMake`
        assertEq(newOrderId, 0);
        // The offer was fully matched and removed from the order book
        assertOrderCounts(callDC2000OrderBook, 1, 0);
        // Now let's check the order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(
                callDC2000OrderBook, isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
    }

    /**
     * Test the `sweepAndMake` function for "Inconsistent component orders" case.
     * This should revert with the message "Inconsistent component orders".
     */
    function testSweepAndMakeInconsistentComponentOrders() public {
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 expiration = mockTimeOracle.getTime() + 1 hours;
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = callDC2000OrderBook.make(-5 ether, 1 ether, expiration);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = callDC2000OrderBook.make(5 ether, 1 ether, expiration);
        // We now have 2 orders on the book
        assertOrderCounts(callDC2000OrderBook, 1, 1);
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
        callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
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
        callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
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
        callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
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
        callDC2000OrderBook.sweepAndMake(forceFunding, 0, makers, toMake);
    }

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles full order matching and no make.
     * This is a test specifically for single collateral option where all participants deposited collateral.
     */
    function testSweepAndMakeNoMakeSingleCollateral() public {
        // Order book should be empty at first
        assertOrderCounts(callSC3000OrderBook, 0, 0);
        oracleEthUsd.setMockPrice(3000 * 10 ** oracleEthUsd.decimals());
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        uint256 longOptionId = callSC3000OrderBook.longOptionId();
        // Account1 makes an offer
        vm.startPrank(account1);
        uint256 offerId = callSC3000OrderBook.make(-5 ether, 1 ether, oneHourExpiration);
        collaterals.deposit(longOptionId, 0, 10 ether);
        // Account2 places a bid
        vm.startPrank(account2);
        uint256 bidId = callSC3000OrderBook.make(5 ether, 1 ether, oneHourExpiration);
        collaterals.deposit(longOptionId, 0, 10 ether);
        // We now have 2 orders on the book
        assertOrderCounts(callSC3000OrderBook, 1, 1);
        // Prepare the sweep and make to fully take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(0, 0, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        // collaterals.deposit(longOptionId, 0, 10 ether); // No need - forced funding
        bool forceFunding = true;
        // Approve the underlying collateral transfer from this contract to the order book
        WETH.approve(address(callSC3000OrderBook), 10 ether);
        uint256 newOrderId =
            callSC3000OrderBook.sweepAndMake(forceFunding, 1 ether, /*all in underlying*/ makers, toMake);
        // no new order ID since no `toMake`
        assertEq(newOrderId, 0);
        // The offer was fully matched and removed from the order book
        assertOrderCounts(callSC3000OrderBook, 1, 0);
        // Now let's check the order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(
                callSC3000OrderBook, isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
    }

    /**
     * Test the `sweepAndMake` function to ensure it correctly handles put on single collateral.
     */
    function testSweepAndMakePutNoMakeSingleCollateral() public {
        // Order book should be empty at first
        assertOrderCounts(putSC3000OrderBook, 0, 0);
        oracleEthUsd.setMockPrice(3000 * 10 ** oracleEthUsd.decimals());
        uint256 twoHourExpiration = mockTimeOracle.getTime() + 2 hours;
        uint256 longOptionId = putSC3000OrderBook.longOptionId();
        // Account1 makes an offer (matching)
        vm.startPrank(account1);
        uint256 offerId = putSC3000OrderBook.make(-5 ether, 1 ether, oneHourExpiration);
        collaterals.deposit(longOptionId, 15000 * 10 ** USDC.decimals(), 0);
        // Account2 places a bid (not matching)
        vm.startPrank(account2);
        uint256 bidId = putSC3000OrderBook.make(5 ether, 1 ether, oneHourExpiration);
        collaterals.deposit(longOptionId, 15000 * 10 ** USDC.decimals(), 0);
        // We now have 2 orders on the book
        assertOrderCounts(putSC3000OrderBook, 1, 1);
        // Prepare the sweep and make to fully take from offerId
        TTakerEntry[] memory makers = new TTakerEntry[](1);
        makers[0] = TTakerEntry(offerId, 5 ether, 1 ether);
        TMakerEntry memory toMake = TMakerEntry(0, 0, twoHourExpiration);
        // Prepare the account3 for the sweep and make
        vm.startPrank(account3);
        bool forceFunding = true;
        // Approve the base collateral transfer from this contract to the order book
        USDC.approve(address(putSC3000OrderBook), 6 * 10 ** USDC.decimals());
        uint256 newOrderId = putSC3000OrderBook.sweepAndMake(forceFunding, 0 ether, /*all in base*/ makers, toMake);
        // no new order ID since no `toMake`
        assertEq(newOrderId, 0);
        // The offer was fully matched and removed from the order book
        assertOrderCounts(putSC3000OrderBook, 1, 0);
        // Now let's check the order book item in detail to verify that
        // The bid wasn't matching and shouldn't have been touched
        {
            bool isBid = true;
            int256 expectedAmount = 5 ether;
            uint256 expectedPrice = 1 ether;
            uint256 expectedExpiration = oneHourExpiration;
            address expectedOwner = account2;
            assertOrder(
                putSC3000OrderBook, isBid, bidId, expectedAmount, expectedPrice, expectedExpiration, expectedOwner
            );
        }
    }

    /**
     * Test the vanish function with a valid liquidation.
     * Ensures that calling vanish correctly processes the list of orders and liquidates up to the specified amount.
     */
    function testVanishValid() public {
        // Set up the order book with initial orders
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        uint256 shortOptionId = options.getOpposite(longOptionId);
        uint256 collateralsId = collaterals.getId(shortOptionId, true);
        // Account1 makes an offer
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        callDC2000OrderBook.make(-1 ether, 1 ether, oneHourExpiration);
        // Account2 places bids
        vm.startPrank(account2);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        uint256 bidId1 = callDC2000OrderBook.make(2 ether, 1 ether, oneHourExpiration);
        uint256 bidId2 = callDC2000OrderBook.make(3 ether, 1 ether, oneHourExpiration);
        // We now have 3 orders on the book
        assertOrderCounts(callDC2000OrderBook, 2, 1);
        // Check the balances before
        uint256 collateralsBalanceBefore = collaterals.balanceOf(account3, collateralsId);
        uint256 optionsBalanceBefore = options.balanceOf(account3, shortOptionId);
        assertEq(collateralsBalanceBefore, 0);
        assertEq(optionsBalanceBefore, 0);
        // Prepare the vanish operation
        TTakerEntry[] memory makers = new TTakerEntry[](2);
        makers[0] = TTakerEntry(bidId2, -3 ether, 1 ether);
        makers[1] = TTakerEntry(bidId1, -2 ether, 1 ether);
        // Execute the vanish operation
        vm.startPrank(account3);
        callDC2000OrderBook.vanish(account3, makers, 5 ether);
        // The two bids were matched
        assertOrderCounts(callDC2000OrderBook, 0, 1);
        // The account3 balances increased
        uint256 collateralsBalanceAfter = collaterals.balanceOf(account3, collateralsId);
        uint256 optionsBalanceAfter = options.balanceOf(account3, shortOptionId);
        assertEq(collateralsBalanceAfter, 4985000); // amount in 6 decimals minus the fees
        assertEq(optionsBalanceAfter, 5 * 10 ** 18); // amount in 18 decimals
    }

    /**
     * Test the vanish function with an oversold condition.
     * Ensures that calling vanish with a specified amount lower than the orders total reverts with "Vanish oversold".
     */
    function testVanishOversold() public {
        // Set up the order book with initial orders
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        // Account1 places bids
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        uint256 bidId1 = callDC2000OrderBook.make(2 ether, 1 ether, oneHourExpiration);
        uint256 bidId2 = callDC2000OrderBook.make(3 ether, 1 ether, oneHourExpiration);
        // We now have 2 bids on the book
        assertOrderCounts(callDC2000OrderBook, 2, 0);
        // Prepare the vanish operation
        TTakerEntry[] memory makers = new TTakerEntry[](2);
        makers[0] = TTakerEntry(bidId2, -3 ether, 1 ether);
        makers[1] = TTakerEntry(bidId1, -2 ether, 1 ether);
        // Execute the vanish operation expecting a revert
        vm.startPrank(account2);
        vm.expectRevert("Vanish oversold");
        callDC2000OrderBook.vanish(account2, makers, 4 ether);
    }

    /**
     * Test the `vanish` function for "Inconsistent component orders" case.
     * This should revert with the message "Inconsistent component orders".
     */
    function testVanishInconsistentComponentOrders() public {
        oracleEthUsd.setMockPrice(2000 * 10 ** oracleEthUsd.decimals());
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        // Account1 places bids
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, 10000 * 10 ** USDC.decimals(), 10 ether);
        uint256 bidId1 = callDC2000OrderBook.make(2 ether, 1 ether, oneHourExpiration);
        uint256 bidId2 = callDC2000OrderBook.make(3 ether, 1 ether, oneHourExpiration);
        // We now have 2 bids on the book
        assertOrderCounts(callDC2000OrderBook, 2, 0);
        // Prepare the vanish operation with inconsistent maker amounts
        TTakerEntry[] memory makers = new TTakerEntry[](2);
        makers[0] = TTakerEntry(bidId1, -1.5 ether, 1 ether); // Negative amount, valid for sell
        makers[1] = TTakerEntry(bidId2, 1.5 ether, 1 ether); // Positive amount, invalid for sell
        // Execute the vanish operation expecting a revert
        vm.startPrank(account2);
        vm.expectRevert("Inconsistent component orders");
        callDC2000OrderBook.vanish(account2, makers, 5 ether);
    }
}

/**
 * Contract for testing the settlement process of options within the OrderBook and ScholesOption contracts.
 */
contract OrderBookSettleTest is BaseTest {
    // Initialize variables for the test
    uint256 baseAmountDeposit;
    uint256 underlyingAmountDeposit = 10 ether;
    uint256 optionPrice = 2;
    uint256 optionPriceUsdc;
    uint256 optionPriceEth = optionPrice * 1 ether;
    uint256 feeAdjustedOptionPriceUsdc;
    int256 makeTakeAmount = 2;

    function setUp() public override {
        super.setUp();
        baseAmountDeposit = 10000 * 10 ** USDC.decimals();
        optionPriceUsdc = optionPrice * 10 ** USDC.decimals();
    }

    /**
     * Tests the process of buying and settling a long call option.
     * - Account1 deposits collateral and places a buy order for a long call option.
     * - Account2 deposits collateral and sells the option by taking Account1's order.
     * - Account1 settles their position.
     * - The test verifies the correct transfer of collateral and the final settlement process after the option expiration.
     */
    function testBuyAndSettleLongCallOption() public {
        // Initialize variables for the test
        uint256 strikePrice = optEthUsdCallDC2000.strike / (10 ** oracleEthUsd.decimals());
        uint256 actualPrice = 2100;
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        // the option taker sells the option for slightly less after applying the fee
        feeAdjustedOptionPriceUsdc = (optionPriceUsdc * (1 ether - callDC2000OrderBook.TAKER_FEE()) / 1 ether);

        // Set the initial mock price of the underlying asset (ETH)
        oracleEthUsd.setMockPrice(actualPrice * 10 ** oracleEthUsd.decimals());

        // Ensure account1 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Ensure account1 has the expected initial token balances
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account1 deposits collateral and prepares to buy a long option
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertCollateralsBalances(collaterals, account1, longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);

        // Account1 places a bid to buy the long option
        uint256 orderId = callDC2000OrderBook.make(makeTakeAmount * 1 ether, optionPriceEth, oneHourExpiration);

        // Ensure account2 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account2, longOptionId, 0, 0);
        // Ensure account2 has the expected initial token balances
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account2 deposits collateral and sells the option to account1 by taking the order
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
        // Account2 takes account1's order and sells the option
        callDC2000OrderBook.take(orderId, -makeTakeAmount * 1 ether, optionPriceEth);

        // Ensure collateral balances reflect the purchase of the option (premium) by account1
        assertCollateralsBalances(
            collaterals,
            account1,
            longOptionId,
            baseAmountDeposit - (uint256(makeTakeAmount) * optionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account2's collateral balances are updated correctly after taking the order and selling the option
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit + (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );

        // Move time forward to after the expiration of the option
        vm.warp(options.getExpiration(longOptionId) + 1);
        // Set the settlement price
        options.setSettlementPrice(longOptionId);
        assertEq(options.getSettlementPrice(longOptionId), actualPrice * 10 ** oracleEthUsd.decimals());
        // Account1 settles their position
        vm.startPrank(account1);
        callDC2000OrderBook.settle(false);

        // Check the balances after settlement to ensure all collateral is withdrawn for account1
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Account2's collateral is untouched after account1 settlement
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit + (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account1's wallet USDC balance reflects the exercised option minus the option price
        assertBalanceOf(
            USDC,
            account1,
            (INITIAL_USDC_BALANCE + uint256(makeTakeAmount) * ((actualPrice - strikePrice) - optionPrice))
                * (10 ** USDC.decimals())
        );
        // which is a profitable operation
        assert(0 < uint256(makeTakeAmount) * ((actualPrice - strikePrice) - optionPrice));
        // Ensure account1's WETH balance remains the same
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // account2's balances remains the same as after the deposit
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
    }

    /**
     * Tests the process of selling and settling a long call option.
     * - Account1 deposits collateral and places a sell order for a long call option.
     * - Account2 deposits collateral and buys the option by taking Account1's sell order.
     * - Account1 settles their position.
     * - The test verifies the correct transfer of collateral and the final settlement process after the option expiration.
     */
    function testSellAndSettleLongCallOption() public {
        // Initialize variables for the test
        uint256 strikePrice = optEthUsdCallDC2000.strike / (10 ** oracleEthUsd.decimals());
        uint256 actualPrice = 1900;
        uint256 longOptionId = callDC2000OrderBook.longOptionId();
        // the option taker buys the option for slightly more after applying the fee
        feeAdjustedOptionPriceUsdc = (optionPriceUsdc * (1 ether + callDC2000OrderBook.TAKER_FEE()) / 1 ether);

        // Set the mock price of the underlying asset (ETH) before placing the sell order
        oracleEthUsd.setMockPrice(actualPrice * 10 ** oracleEthUsd.decimals());

        // Ensure account1 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Ensure account1 has the expected initial token balances
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account1 deposits collateral and prepares to sell a long option
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertCollateralsBalances(collaterals, account1, longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);

        // Account1 places an offer to sell the long option
        uint256 orderId = callDC2000OrderBook.make(-makeTakeAmount * 1 ether, optionPriceEth, oneHourExpiration);

        // Ensure account2 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account2, longOptionId, 0, 0);
        // Ensure account2 has the expected initial token balances
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account2 deposits collateral and buys the option from account1 by taking the sell order
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
        // Account2 takes account1's sell order and buys the option
        callDC2000OrderBook.take(orderId, makeTakeAmount * 1 ether, optionPriceEth);

        // Ensure collateral balances reflect the sale of the option by account1
        assertCollateralsBalances(
            collaterals,
            account1,
            longOptionId,
            baseAmountDeposit + (uint256(makeTakeAmount) * optionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account2's collateral balances are updated correctly after buying the option from account1
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit - (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );

        // Move time forward to after the expiration of the option
        vm.warp(options.getExpiration(longOptionId) + 1);
        // settlement price will be updated automatically within the settle() call
        assertEq(options.getSettlementPrice(longOptionId), 0);
        // Account1 settles their position
        vm.startPrank(account1);
        callDC2000OrderBook.settle(false);
        // settlement price was updated to match with the actual price
        assertEq(options.getSettlementPrice(longOptionId), actualPrice * 10 ** oracleEthUsd.decimals());

        // Check the balances after settlement to ensure all collateral is withdrawn for account1
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Ensure account2's collateral is correctly reflected after account1's settlement
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit - (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account1's USDC balance reflects the option price sold
        assertBalanceOf(
            USDC, account1, (INITIAL_USDC_BALANCE + uint256(makeTakeAmount) * optionPrice) * (10 ** USDC.decimals())
        );
        // Ensure account1's WETH balance accounts stays the same as it's settled to base (USDC)
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // account2's balances remains the same as after the deposit
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
    }

    /**
     * Tests the process of buying and settling a long put option.
     * - Account1 deposits collateral and places a buy order for a long put option.
     * - Account2 deposits collateral and sells the option by taking Account1's order.
     * - Accounts 1 & 2 settle their positions.
     * - The test verifies the correct transfer of collateral and the final settlement process after the option expiration.
     */
    function testBuyAndSettleLongPutOption() public {
        // Initialize variables for the test
        uint256 strikePrice = optEthUsdPutDC2000.strike / (10 ** oracleEthUsd.decimals());
        uint256 actualPrice = 1900;
        uint256 longOptionId = putDC2000OrderBook.longOptionId();
        // the option taker sells the option for slightly less after applying the fee
        feeAdjustedOptionPriceUsdc = (optionPriceUsdc * (1 ether - callDC2000OrderBook.TAKER_FEE()) / 1 ether);

        // Set the initial mock price of the underlying asset (ETH)
        oracleEthUsd.setMockPrice(actualPrice * 10 ** oracleEthUsd.decimals());

        // Ensure account1 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Ensure account1 has the expected initial token balances
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account1 deposits collateral and prepares to buy a long option
        vm.startPrank(account1);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertCollateralsBalances(collaterals, account1, longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        assertBalanceOf(USDC, account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);

        // Account1 places a bid to buy the long put option
        uint256 orderId = putDC2000OrderBook.make(makeTakeAmount * 1 ether, optionPriceEth, oneHourExpiration);

        // Ensure account2 starts with zero collateral balances
        assertCollateralsBalances(collaterals, account2, longOptionId, 0, 0);
        // Ensure account2 has the expected initial token balances
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account2 deposits collateral and sells the option to account1 by taking the order
        vm.startPrank(account2, account2);
        collaterals.deposit(longOptionId, baseAmountDeposit, underlyingAmountDeposit);
        // Ensure the correct amounts are deposited
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
        // Account2 takes account1's order and sells the option
        putDC2000OrderBook.take(orderId, -makeTakeAmount * 1 ether, optionPriceEth);

        // Ensure collateral balances reflect the purchase of the option (premium) by account1
        assertCollateralsBalances(
            collaterals,
            account1,
            longOptionId,
            baseAmountDeposit - (uint256(makeTakeAmount) * optionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account2's collateral balances are updated correctly after taking the order and selling the option
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit + (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );

        // Move time forward to after the expiration of the option
        vm.warp(options.getExpiration(longOptionId) + 1);
        // Set the settlement price
        options.setSettlementPrice(longOptionId);
        assertEq(options.getSettlementPrice(longOptionId), actualPrice * 10 ** oracleEthUsd.decimals());
        // Account1 settles their position
        vm.startPrank(account1);
        putDC2000OrderBook.settle(false);

        // Check the balances after settlement to ensure all collateral is withdrawn for account1
        assertCollateralsBalances(collaterals, account1, longOptionId, 0, 0);
        // Account2's collateral is untouched after account1 settlement
        assertCollateralsBalances(
            collaterals,
            account2,
            longOptionId,
            baseAmountDeposit + (uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc),
            underlyingAmountDeposit
        );
        // Ensure account1's wallet USDC balance reflects the profit (in this case) from the price the change minus the option price
        assertBalanceOf(
            USDC,
            account1,
            (INITIAL_USDC_BALANCE + uint256(makeTakeAmount) * (strikePrice - actualPrice - optionPrice))
                * (10 ** USDC.decimals())
        );
        // Ensure account1's WETH balance accounts stays the same as it's settled to base (USDC)
        assertBalanceOf(WETH, account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        // Account2's balances remains the same as after the deposit
        assertBalanceOf(USDC, account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals() - baseAmountDeposit);
        assertBalanceOf(WETH, account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals() - underlyingAmountDeposit);
        // Account2 settles their position
        vm.startPrank(account2);
        putDC2000OrderBook.settle(false);
        // All collateral is withdrawn for account2
        assertCollateralsBalances(collaterals, account2, longOptionId, 0, 0);
        // Ensure account2's USDC balance reflects the premium received, minus the loss (in this case) from the price change
        assertBalanceOf(
            USDC,
            account2,
            (
                (INITIAL_USDC_BALANCE - uint256(makeTakeAmount) * (strikePrice - actualPrice)) * (10 ** USDC.decimals())
                    + uint256(makeTakeAmount) * feeAdjustedOptionPriceUsdc
            )
        );
        // Ensure account2's WETH balance accounts stays the same as it's settled to base (USDC)
        assertBalanceOf(WETH, account2, (INITIAL_WETH_BALANCE) * 10 ** WETH.decimals());
    }
}
