package com.ecommerce;

/**
 * Represents a single line item in an order: a product SKU, unit price in cents,
 * and quantity ordered.
 */
public class OrderItem {

    private final String sku;
    private final String productName;
    private final int unitPriceCents;  // unit price in integer cents (e.g., 1099 = $10.99)
    private final int quantity;

    public OrderItem(String sku, String productName, int unitPriceCents, int quantity) {
        if (unitPriceCents < 0) throw new IllegalArgumentException("Price cannot be negative");
        if (quantity <= 0)      throw new IllegalArgumentException("Quantity must be positive");
        this.sku = sku;
        this.productName = productName;
        this.unitPriceCents = unitPriceCents;
        this.quantity = quantity;
    }

    public String getSku()          { return sku; }
    public String getProductName()  { return productName; }
    public int getUnitPriceCents()  { return unitPriceCents; }
    public int getQuantity()        { return quantity; }

    /** Returns total price for this line item (unitPrice × quantity), in cents. */
    public int getLineTotalCents() {
        return unitPriceCents * quantity;
    }

    @Override
    public String toString() {
        return String.format("OrderItem{sku='%s', price=%d cents, qty=%d}", sku, unitPriceCents, quantity);
    }
}
