package com.trading;

import java.util.ArrayList;
import java.util.List;

/**
 * Maintains the order book: a sorted list of resting bids and asks.
 *
 * <p>Price-time priority rules:
 * <ul>
 *   <li>Bids (buy orders) are sorted <em>descending</em> by limit price —
 *       the highest bid is at index 0 and is the best (most aggressive) bid.</li>
 *   <li>Asks (sell orders) are sorted <em>ascending</em> by limit price —
 *       the lowest ask is at index 0 and is the best (cheapest) offer.</li>
 * </ul>
 *
 * <p>BUG: both {@code bids} and {@code asks} are plain {@link ArrayList}s.
 * Orders are appended at the end in insertion order without any sorting.
 * As a result, {@link #getBestBid()} and {@link #getBestAsk()} return the
 * first element ever added, not the most aggressive price.  The matching
 * engine therefore matches against stale, incorrect prices.
 *
 * <p>Fix: maintain sorted order on insertion.  Use a
 * {@link java.util.TreeMap} keyed on price (with time as a secondary key),
 * or insert into the {@code ArrayList} at the correct sorted position using
 * a comparator.  The invariant is that {@code getBestBid()} always returns
 * the order with the <em>highest</em> limit price, and {@code getBestAsk()}
 * always returns the order with the <em>lowest</em> limit price.
 */
public class OrderBook {

    private final List<Order> bids = new ArrayList<>();  // BUG: unsorted; should be sorted HIGH→LOW
    private final List<Order> asks = new ArrayList<>();  // BUG: unsorted; should be sorted LOW→HIGH

    /** Adds a new BID (buy) order to the book. */
    public void addBid(Order order) {
        if (order.getSide() != Order.Side.BID) {
            throw new IllegalArgumentException("Expected BID order, got: " + order.getSide());
        }
        bids.add(order);   // BUG: just appends — no sorted insertion
    }

    /** Adds a new ASK (sell) order to the book. */
    public void addAsk(Order order) {
        if (order.getSide() != Order.Side.ASK) {
            throw new IllegalArgumentException("Expected ASK order, got: " + order.getSide());
        }
        asks.add(order);   // BUG: just appends — no sorted insertion
    }

    /**
     * Returns the best (highest-priced) resting bid, or {@code null} if the bid
     * side is empty.
     */
    public Order getBestBid() {
        return bids.isEmpty() ? null : bids.get(0);  // BUG: get(0) is first-inserted, not highest price
    }

    /**
     * Returns the best (lowest-priced) resting ask, or {@code null} if the ask
     * side is empty.
     */
    public Order getBestAsk() {
        return asks.isEmpty() ? null : asks.get(0);  // BUG: get(0) is first-inserted, not lowest price
    }

    /** Removes the best bid from the book (call after it has been fully matched). */
    public void removeBestBid() {
        if (!bids.isEmpty()) bids.remove(0);
    }

    /** Removes the best ask from the book (call after it has been fully matched). */
    public void removeBestAsk() {
        if (!asks.isEmpty()) asks.remove(0);
    }

    public boolean hasBids() { return !bids.isEmpty(); }
    public boolean hasAsks() { return !asks.isEmpty(); }

    public int getBidDepth() { return bids.size(); }
    public int getAskDepth() { return asks.size(); }
}
