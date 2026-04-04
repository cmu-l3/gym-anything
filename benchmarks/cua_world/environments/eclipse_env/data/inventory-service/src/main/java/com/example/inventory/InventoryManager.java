package com.example.inventory;

import com.example.inventory.model.Product;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Manages stock quantities per product SKU.
 *
 * BUG 1: Uses HashMap (not thread-safe).
 * BUG 2: removeStock() has a check-then-act race condition:
 *   the check (getOrDefault) and the update (put) are two separate operations —
 *   another thread can change the value between them, causing stock to go negative.
 *   The entire operation must be atomic. Use ConcurrentHashMap.compute() or
 *   synchronized block to make it atomic.
 */
public class InventoryManager {

    // BUG: HashMap is not thread-safe
    private final Map<String, Integer> stockLevels = new HashMap<>();

    public void setStock(String sku, int quantity) {
        stockLevels.put(sku, quantity);
    }

    public int getStock(String sku) {
        return stockLevels.getOrDefault(sku, 0);
    }

    /**
     * Remove quantity from stock. Returns true on success, false if insufficient stock.
     *
     * BUG: check-then-act is not atomic — race condition allows overdraft.
     */
    public boolean removeStock(String sku, int quantity) {
        int current = stockLevels.getOrDefault(sku, 0);  // Step 1: read
        if (current < quantity) {
            return false;
        }
        // BUG: Another thread can reduce stock between Step 1 and Step 2
        stockLevels.put(sku, current - quantity);         // Step 2: write
        return true;
    }

    public void addStock(String sku, int quantity) {
        stockLevels.merge(sku, quantity, Integer::sum);
    }

    public boolean hasStock(String sku, int requiredQuantity) {
        return stockLevels.getOrDefault(sku, 0) >= requiredQuantity;
    }

    public Map<String, Integer> getAllStockLevels() {
        return new HashMap<>(stockLevels);
    }
}
