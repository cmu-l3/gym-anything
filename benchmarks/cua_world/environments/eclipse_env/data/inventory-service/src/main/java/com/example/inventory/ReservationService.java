package com.example.inventory;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Handles temporary stock reservations for pending orders.
 *
 * BUG: Multiple compound operations on shared state are not synchronized.
 * - createReservation() reads and writes two separate maps without synchronization —
 *   another thread can interleave and create duplicate reservations for the same stock.
 * - cancelReservation() checks existence and removes without synchronization.
 * All mutating methods must be synchronized (or use appropriate locking) to prevent
 * double-booking and reservation leaks.
 */
public class ReservationService {

    // BUG: No synchronization on compound read+write operations
    private final Map<String, Integer> reservedQuantities = new HashMap<>();
    private final Set<String> activeReservationIds = new HashSet<>();
    private final InventoryManager inventoryManager;

    public ReservationService(InventoryManager inventoryManager) {
        this.inventoryManager = inventoryManager;
    }

    /**
     * Creates a reservation for sku/quantity. Returns reservation ID on success, null on failure.
     * BUG: Not synchronized — double booking possible under concurrent load.
     */
    public String createReservation(String sku, int quantity) {
        if (!inventoryManager.hasStock(sku, quantity)) {
            return null;
        }
        // BUG: Another thread can pass the hasStock check simultaneously
        boolean removed = inventoryManager.removeStock(sku, quantity);
        if (!removed) return null;

        String reservationId = UUID.randomUUID().toString();
        reservedQuantities.put(reservationId, quantity);
        activeReservationIds.add(reservationId);
        return reservationId;
    }

    /**
     * Cancels an active reservation, returning stock.
     * BUG: Not synchronized — reservation can be cancelled twice.
     */
    public boolean cancelReservation(String reservationId, String sku) {
        if (!activeReservationIds.contains(reservationId)) {  // Step 1
            return false;
        }
        // BUG: Another thread can also pass Step 1 for the same reservationId
        Integer qty = reservedQuantities.remove(reservationId);  // Step 2
        activeReservationIds.remove(reservationId);
        if (qty != null) {
            inventoryManager.addStock(sku, qty);
        }
        return qty != null;
    }

    public boolean isActive(String reservationId) {
        return activeReservationIds.contains(reservationId);
    }

    public int getReservedCount() {
        return activeReservationIds.size();
    }
}
