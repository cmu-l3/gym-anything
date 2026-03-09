package com.example.inventory;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class InventoryManagerTest {

    private InventoryManager manager;

    @BeforeEach
    void setUp() {
        manager = new InventoryManager();
        manager.setStock("SKU-001", 100);
        manager.setStock("SKU-002", 50);
    }

    @Test
    void getStock_returnsCorrectQuantity() {
        assertEquals(100, manager.getStock("SKU-001"));
        assertEquals(50, manager.getStock("SKU-002"));
    }

    @Test
    void removeStock_success() {
        assertTrue(manager.removeStock("SKU-001", 10));
        assertEquals(90, manager.getStock("SKU-001"));
    }

    @Test
    void removeStock_insufficientStock_returnsFalse() {
        assertFalse(manager.removeStock("SKU-001", 200));
        assertEquals(100, manager.getStock("SKU-001"));
    }

    @Test
    void addStock_increasesQuantity() {
        manager.addStock("SKU-001", 50);
        assertEquals(150, manager.getStock("SKU-001"));
    }
}
