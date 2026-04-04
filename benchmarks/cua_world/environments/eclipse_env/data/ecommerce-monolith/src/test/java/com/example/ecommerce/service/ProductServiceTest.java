package com.example.ecommerce.service;

import com.example.ecommerce.model.Product;
import com.example.ecommerce.repository.ProductRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

class ProductServiceTest {

    private ProductService service;

    @BeforeEach
    void setUp() {
        service = new ProductService(new ProductRepository());
    }

    @Test
    void getAllProducts_returnsSeedData() {
        List<Product> products = service.getAllProducts();
        assertFalse(products.isEmpty());
        assertTrue(products.size() >= 5);
    }

    @Test
    void createProduct_savesAndReturns() {
        Product p = service.createProduct("SKU-TEST", "Test Item", "desc",
            new BigDecimal("9.99"), 10, "Test");
        assertTrue(p.getId() > 0);
        assertEquals("SKU-TEST", p.getSku());
    }

    @Test
    void createProduct_duplicateSku_throws() {
        assertThrows(IllegalStateException.class, () ->
            service.createProduct("SKU-001", "Dup", "desc",
                new BigDecimal("1.00"), 1, "Electronics"));
    }

    @Test
    void updateStock_reducesQuantity() {
        List<Product> products = service.getAllProducts();
        Product first = products.get(0);
        int before = first.getStockQuantity();
        service.updateStock(first.getId(), -5);
        Optional<Product> updated = service.getProduct(first.getId());
        assertTrue(updated.isPresent());
        assertEquals(before - 5, updated.get().getStockQuantity());
    }
}
