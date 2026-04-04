package com.example.inventory.model;

import java.math.BigDecimal;

public class Product {
    private final int id;
    private final String sku;
    private String name;
    private BigDecimal price;

    public Product(int id, String sku, String name, BigDecimal price) {
        this.id = id;
        this.sku = sku;
        this.name = name;
        this.price = price;
    }

    public int getId() { return id; }
    public String getSku() { return sku; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    @Override
    public String toString() {
        return "Product{id=" + id + ", sku='" + sku + "', name='" + name + "'}";
    }
}
