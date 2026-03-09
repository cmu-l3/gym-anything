package com.example.inventory;

import com.example.inventory.model.Product;
import java.math.BigDecimal;

public class InventoryApplication {

    public static void main(String[] args) {
        ProductCatalog catalog = new ProductCatalog();
        InventoryManager manager = new InventoryManager();
        ReservationService reservations = new ReservationService(manager);
        StockCounter counter = new StockCounter();

        // Seed some products
        catalog.addProduct(new Product(1, "SKU-001", "Widget A", new BigDecimal("9.99")));
        catalog.addProduct(new Product(2, "SKU-002", "Widget B", new BigDecimal("19.99")));
        manager.setStock("SKU-001", 1000);
        manager.setStock("SKU-002", 500);

        System.out.println("Inventory Service started with " + catalog.size() + " products");
    }
}
