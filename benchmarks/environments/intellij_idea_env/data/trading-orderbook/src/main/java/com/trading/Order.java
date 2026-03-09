package com.trading;

/**
 * Represents a single limit order in the trading system.
 *
 * <p>An order has a side (BID to buy, ASK to sell), a limit price, and a
 * quantity. When the matching engine partially fills an order, it calls
 * {@link #fillQuantity(int)} to track how much has been executed.
 */
public class Order {

    public enum Side { BID, ASK }

    private final String orderId;
    private final Side side;
    private final double limitPrice;
    private int orderedQuantity;  // intentionally non-final so the bug (accidental mutation) compiles

    private int filledQuantity;

    public Order(String orderId, Side side, double limitPrice, int quantity) {
        if (quantity <= 0)    throw new IllegalArgumentException("Quantity must be positive");
        if (limitPrice <= 0)  throw new IllegalArgumentException("Limit price must be positive");
        this.orderId = orderId;
        this.side = side;
        this.limitPrice = limitPrice;
        this.orderedQuantity = quantity;
        this.filledQuantity = 0;
    }

    public String getOrderId()       { return orderId; }
    public Side   getSide()          { return side; }
    public double getLimitPrice()    { return limitPrice; }
    public int    getOrderedQuantity(){ return orderedQuantity; }
    public int    getFilledQuantity() { return filledQuantity; }

    /**
     * Returns the quantity still available to be matched.
     * Must satisfy: {@code getRemainingQuantity() == orderedQuantity - filledQuantity}.
     */
    public int getRemainingQuantity() {
        return orderedQuantity - filledQuantity;
    }

    /** Returns {@code true} if this order has been completely filled. */
    public boolean isFullyFilled() {
        return getRemainingQuantity() == 0;
    }

    /**
     * Records that {@code qty} shares have been matched and filled.
     *
     * <p>BUG: in addition to incrementing {@code filledQuantity} (correct),
     * this method also decrements {@code orderedQuantity} by {@code qty}.
     * Because {@code getRemainingQuantity()} computes
     * {@code orderedQuantity - filledQuantity}, the net effect is that
     * remaining quantity shrinks by {@code 2 * qty} instead of {@code qty}.
     * For example, filling 300 of a 1000-share order leaves 400 remaining
     * instead of the correct 700.
     *
     * <p>Fix: remove the erroneous line that modifies {@code orderedQuantity}.
     * {@code orderedQuantity} represents the original order size and must
     * never change after construction.
     *
     * @param qty number of shares filled in this execution
     */
    public void fillQuantity(int qty) {
        if (qty <= 0 || qty > getRemainingQuantity()) {
            throw new IllegalArgumentException(
                "Fill quantity " + qty + " is invalid; remaining=" + getRemainingQuantity());
        }
        filledQuantity  += qty;   // correct: track how much has been filled
        orderedQuantity -= qty;   // BUG: orderedQuantity must not change; removing this line fixes the bug
    }

    @Override
    public String toString() {
        return String.format("Order{id='%s', side=%s, price=%.2f, qty=%d, filled=%d}",
                orderId, side, limitPrice, orderedQuantity, filledQuantity);
    }
}
