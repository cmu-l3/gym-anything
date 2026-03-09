package com.trading;

import java.util.ArrayList;
import java.util.List;

/**
 * Price-time priority matching engine.  Continuously attempts to match the
 * best resting bid against the best resting ask.  A match occurs when the
 * bid's limit price is at least as high as the ask's limit price.
 *
 * <p>The execution price is always the <em>resting</em> (passive) side's price.
 */
public class MatchingEngine {

    private final OrderBook book;
    private final List<Trade> executedTrades = new ArrayList<>();

    public MatchingEngine(OrderBook book) {
        this.book = book;
    }

    /**
     * Runs one matching pass: matches the current best bid against the best ask,
     * executes a trade if prices cross, and repeats until no more matches exist.
     *
     * <p>BUG: the price-cross condition uses strict {@code >} instead of {@code >=}.
     * This means that two orders at <em>exactly</em> the same price are never matched —
     * the most common case in real order books where a buyer and seller agree on a
     * precise price.  The condition must be {@code >=} to also match at-par orders.
     *
     * <p>Fix: change {@code bid.getLimitPrice() > ask.getLimitPrice()} to
     * {@code bid.getLimitPrice() >= ask.getLimitPrice()}.
     */
    public void runMatchingCycle() {
        while (book.hasBids() && book.hasAsks()) {
            Order bid = book.getBestBid();
            Order ask = book.getBestAsk();

            // BUG: strict > excludes at-par matches; should be >=
            if (bid.getLimitPrice() > ask.getLimitPrice()) {
                int fillQty = Math.min(bid.getRemainingQuantity(), ask.getRemainingQuantity());
                double execPrice = ask.getLimitPrice();  // passive side sets the price

                bid.fillQuantity(fillQty);
                ask.fillQuantity(fillQty);

                executedTrades.add(new Trade(bid.getOrderId(), ask.getOrderId(), execPrice, fillQty));

                if (bid.isFullyFilled()) book.removeBestBid();
                if (ask.isFullyFilled()) book.removeBestAsk();
            } else {
                break;  // no more crossable prices
            }
        }
    }

    /** Returns all trades executed so far in this engine instance. */
    public List<Trade> getExecutedTrades() {
        return new ArrayList<>(executedTrades);
    }

    /** Returns the number of trades executed so far. */
    public int getTradeCount() {
        return executedTrades.size();
    }
}
