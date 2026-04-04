package com.example.inventory;

import com.example.inventory.model.Product;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * In-memory catalog of all products.
 *
 * BUG: Uses HashMap which is not thread-safe.
 * Concurrent reads and writes can cause HashMap internal state corruption
 * (infinite loop, NullPointerException, data loss).
 * Replace with java.util.concurrent.ConcurrentHashMap.
 */
public class ProductCatalog {

    // BUG: HashMap is not thread-safe — use ConcurrentHashMap
    private final Map<String, Product> productsBySku = new HashMap<>();
    private final Map<Integer, Product> productsById = new HashMap<>();

    public void addProduct(Product product) {
        productsBySku.put(product.getSku(), product);
        productsById.put(product.getId(), product);
    }

    public Optional<Product> findBySku(String sku) {
        return Optional.ofNullable(productsBySku.get(sku));
    }

    public Optional<Product> findById(int id) {
        return Optional.ofNullable(productsById.get(id));
    }

    public Collection<Product> getAllProducts() {
        return new ArrayList<>(productsBySku.values());
    }

    public int size() {
        return productsBySku.size();
    }

    public boolean remove(String sku) {
        Product removed = productsBySku.remove(sku);
        if (removed != null) {
            productsById.remove(removed.getId());
            return true;
        }
        return false;
    }
}
