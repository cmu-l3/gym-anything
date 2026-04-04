package com.example.ecommerce.repository;

import com.example.ecommerce.model.Product;

import java.util.*;
import java.math.BigDecimal;

public class ProductRepository {
    private final Map<Integer, Product> store = new HashMap<>();
    private int nextId = 1;

    public ProductRepository() {
        // Seed some products
        save(new Product(0, "SKU-001", "Wireless Keyboard", "Compact wireless keyboard", new BigDecimal("49.99"), 100, "Electronics"));
        save(new Product(0, "SKU-002", "USB-C Hub", "7-port USB-C hub", new BigDecimal("39.99"), 50, "Electronics"));
        save(new Product(0, "SKU-003", "Desk Lamp", "LED adjustable desk lamp", new BigDecimal("29.99"), 75, "Office"));
        save(new Product(0, "SKU-004", "Notebook Set", "Pack of 3 spiral notebooks", new BigDecimal("12.99"), 200, "Office"));
        save(new Product(0, "SKU-005", "Mechanical Pencil", "0.5mm mechanical pencil", new BigDecimal("8.99"), 300, "Office"));
    }

    public Product save(Product product) {
        if (product.getId() == 0) {
            product.setId(nextId++);
        }
        store.put(product.getId(), product);
        return product;
    }

    public Optional<Product> findById(int id) {
        return Optional.ofNullable(store.get(id));
    }

    public Optional<Product> findBySku(String sku) {
        return store.values().stream().filter(p -> p.getSku().equals(sku)).findFirst();
    }

    public List<Product> findAll() {
        return new ArrayList<>(store.values());
    }

    public List<Product> findByCategory(String category) {
        List<Product> result = new ArrayList<>();
        for (Product p : store.values()) {
            if (category.equals(p.getCategory())) result.add(p);
        }
        return result;
    }

    public boolean delete(int id) {
        return store.remove(id) != null;
    }
}
