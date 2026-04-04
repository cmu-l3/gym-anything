package com.example.ecommerce.service;

import com.example.ecommerce.model.Product;
import com.example.ecommerce.repository.ProductRepository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

public class ProductService {

    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public Product createProduct(String sku, String name, String description,
                                  BigDecimal price, int quantity, String category) {
        if (sku == null || sku.isBlank()) throw new IllegalArgumentException("SKU required");
        if (price == null || price.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Price must be non-negative");
        productRepository.findBySku(sku).ifPresent(p -> {
            throw new IllegalStateException("SKU already exists: " + sku);
        });
        return productRepository.save(new Product(0, sku, name, description, price, quantity, category));
    }

    public Optional<Product> getProduct(int id) {
        return productRepository.findById(id);
    }

    public List<Product> getAllProducts() {
        return productRepository.findAll();
    }

    public List<Product> getProductsByCategory(String category) {
        return productRepository.findByCategory(category);
    }

    public Product updateStock(int productId, int delta) {
        Product p = productRepository.findById(productId)
            .orElseThrow(() -> new IllegalArgumentException("Product not found: " + productId));
        int newQty = p.getStockQuantity() + delta;
        if (newQty < 0) throw new IllegalStateException("Insufficient stock");
        p.setStockQuantity(newQty);
        return productRepository.save(p);
    }
}
