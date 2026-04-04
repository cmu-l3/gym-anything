package com.trading;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.List;

/**
 * Tests for the order book and matching engine.  Covers:
 *  - Best-bid/ask priority (OrderBook sorting bug)
 *  - At-par price matching (MatchingEngine comparison bug)
 *  - Partial-fill quantity tracking (Order.fillQuantity bug)
 */
public class OrderBookTest {

    // -----------------------------------------------------------------------
    // Baseline: empty book behaviour (should pass before any fixes)
    // -----------------------------------------------------------------------

    @Test
    public void testEmptyBookHasNoBestBidOrAsk() {
        OrderBook book = new OrderBook();
        assertNull("Empty book should have no best bid",  book.getBestBid());
        assertNull("Empty book should have no best ask",  book.getBestAsk());
        assertFalse("Empty book should have no bids",     book.hasBids());
        assertFalse("Empty book should have no asks",     book.hasAsks());
    }

    // -----------------------------------------------------------------------
    // OrderBook sorting test — exercises the ArrayList (unsorted) bug
    // -----------------------------------------------------------------------

    @Test
    public void testBestBidIsHighestPrice() {
        OrderBook book = new OrderBook();

        // Add bids in non-sorted order: 99, 101, 100
        // Best bid must always be the HIGHEST price (101.0)
        book.addBid(new Order("B1", Order.Side.BID, 99.0,  500));
        book.addBid(new Order("B2", Order.Side.BID, 101.0, 200));
        book.addBid(new Order("B3", Order.Side.BID, 100.0, 300));

        Order bestBid = book.getBestBid();
        assertNotNull("Best bid must not be null when bids exist", bestBid);
        assertEquals(
            "Best bid must be the order with the HIGHEST limit price (101.0), not the first inserted (99.0). " +
            "Fix: OrderBook must maintain bids in descending price order (e.g., use a sorted structure).",
            101.0, bestBid.getLimitPrice(), 0.001
        );
    }

    @Test
    public void testBestAskIsLowestPrice() {
        OrderBook book = new OrderBook();

        // Add asks in non-sorted order: 102, 100, 101
        // Best ask must always be the LOWEST price (100.0)
        book.addAsk(new Order("A1", Order.Side.ASK, 102.0, 400));
        book.addAsk(new Order("A2", Order.Side.ASK, 100.0, 100));
        book.addAsk(new Order("A3", Order.Side.ASK, 101.0, 200));

        Order bestAsk = book.getBestAsk();
        assertNotNull("Best ask must not be null when asks exist", bestAsk);
        assertEquals(
            "Best ask must be the order with the LOWEST limit price (100.0), not the first inserted (102.0). " +
            "Fix: OrderBook must maintain asks in ascending price order.",
            100.0, bestAsk.getLimitPrice(), 0.001
        );
    }

    // -----------------------------------------------------------------------
    // Matching engine at-par test — exercises the > vs >= bug
    // -----------------------------------------------------------------------

    @Test
    public void testAtParPriceOrdersAreMatched() {
        OrderBook book = new OrderBook();
        MatchingEngine engine = new MatchingEngine(book);

        // Buyer willing to pay exactly $100.00; seller asking exactly $100.00
        // These orders MUST match (bid price == ask price)
        book.addBid(new Order("BID-1", Order.Side.BID, 100.0, 500));
        book.addAsk(new Order("ASK-1", Order.Side.ASK, 100.0, 500));

        engine.runMatchingCycle();

        List<Trade> trades = engine.getExecutedTrades();
        assertEquals(
            "A BID at $100 and an ASK at $100 must produce exactly one trade. " +
            "Fix: MatchingEngine.runMatchingCycle() uses strict > for price comparison; " +
            "change to >= so that at-par orders are matched.",
            1, trades.size()
        );
        assertEquals("Execution price must be $100.00", 100.0, trades.get(0).getExecutionPrice(), 0.001);
        assertEquals("Execution quantity must be 500",  500,   trades.get(0).getExecutionQuantity());
    }

    @Test
    public void testCrossedPriceOrdersAreMatched() {
        // Buyer willing to pay $101 meets seller asking $100 → must match at ask price $100
        // This should pass even with the > bug (101 > 100 is true)
        OrderBook book = new OrderBook();
        MatchingEngine engine = new MatchingEngine(book);

        book.addBid(new Order("BID-2", Order.Side.BID, 101.0, 200));
        book.addAsk(new Order("ASK-2", Order.Side.ASK, 100.0, 200));

        engine.runMatchingCycle();

        assertEquals("Crossed orders must always match", 1, engine.getTradeCount());
        assertEquals("Execution at passive (ask) price $100", 100.0,
                     engine.getExecutedTrades().get(0).getExecutionPrice(), 0.001);
    }

    // -----------------------------------------------------------------------
    // Partial fill test — exercises Order.fillQuantity bug
    // -----------------------------------------------------------------------

    @Test
    public void testPartialFillTracksRemainingCorrectly() {
        Order order = new Order("ORD-1", Order.Side.BID, 100.0, 1000);

        assertEquals("Fresh order: remaining should equal ordered qty", 1000, order.getRemainingQuantity());
        assertFalse("Fresh order should not be fully filled",            order.isFullyFilled());

        order.fillQuantity(300);

        assertEquals(
            "After filling 300 of 1000, remaining must be 700. " +
            "Fix: Order.fillQuantity() must NOT modify orderedQuantity — that field is the original order " +
            "size and is immutable. Remove the line 'orderedQuantity -= qty;'",
            700, order.getRemainingQuantity()
        );
        assertFalse("300/1000 filled — order should not be fully filled", order.isFullyFilled());

        order.fillQuantity(700);

        assertEquals("After filling 1000/1000, remaining must be 0", 0, order.getRemainingQuantity());
        assertTrue("Order fully filled", order.isFullyFilled());
    }
}
