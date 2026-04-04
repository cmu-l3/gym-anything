package com.trading;

/**
 * Represents an executed trade: a matched portion of a BID and ASK order.
 * The execution price is always the resting order's limit price (passive side).
 */
public class Trade {

    private final String buyOrderId;
    private final String sellOrderId;
    private final double executionPrice;
    private final int    executionQuantity;

    public Trade(String buyOrderId, String sellOrderId, double executionPrice, int executionQuantity) {
        this.buyOrderId        = buyOrderId;
        this.sellOrderId       = sellOrderId;
        this.executionPrice    = executionPrice;
        this.executionQuantity = executionQuantity;
    }

    public String getBuyOrderId()      { return buyOrderId; }
    public String getSellOrderId()     { return sellOrderId; }
    public double getExecutionPrice()  { return executionPrice; }
    public int    getExecutionQuantity(){ return executionQuantity; }

    @Override
    public String toString() {
        return String.format("Trade{buy='%s', sell='%s', price=%.2f, qty=%d}",
                buyOrderId, sellOrderId, executionPrice, executionQuantity);
    }
}
