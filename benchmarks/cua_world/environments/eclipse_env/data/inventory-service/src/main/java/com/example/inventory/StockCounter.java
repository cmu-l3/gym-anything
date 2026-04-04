package com.example.inventory;

/**
 * Tracks a running total of items processed (sold, received, reserved).
 *
 * BUG: Uses a plain int field for the counter, which is NOT thread-safe.
 * Under concurrent access the increment and read operations are non-atomic,
 * causing lost updates. Replace with java.util.concurrent.atomic.AtomicInteger.
 */
public class StockCounter {

    // BUG: plain int is not thread-safe — use AtomicInteger
    private int totalProcessed = 0;
    private int totalReceived = 0;
    private int totalSold = 0;

    public void recordSale(int quantity) {
        totalSold += quantity;
        totalProcessed += quantity;
    }

    public void recordReceipt(int quantity) {
        totalReceived += quantity;
        totalProcessed += quantity;
    }

    public int getTotalProcessed() { return totalProcessed; }
    public int getTotalReceived() { return totalReceived; }
    public int getTotalSold() { return totalSold; }

    public void reset() {
        totalProcessed = 0;
        totalReceived = 0;
        totalSold = 0;
    }
}
