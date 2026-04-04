package com.ecommerce;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Represents a customer order containing one or more line items.
 * Orders are created in PENDING state and must be validated and processed
 * before they are fulfilled.
 */
public class Order {

    public enum Status { PENDING, CONFIRMED, SHIPPED, CANCELLED }

    private final String orderId;
    private final Customer customer;
    private final List<OrderItem> items;
    private Status status;

    public Order(String orderId, Customer customer) {
        this.orderId = orderId;
        this.customer = customer;
        this.items = new ArrayList<>();
        this.status = Status.PENDING;
    }

    public void addItem(OrderItem item) {
        if (item == null) throw new IllegalArgumentException("Cannot add null item to order");
        items.add(item);
    }

    public String getOrderId()      { return orderId; }
    public Customer getCustomer()   { return customer; }
    public Status getStatus()       { return status; }
    public void setStatus(Status s) { this.status = s; }

    /** Returns an unmodifiable view of the order's line items. */
    public List<OrderItem> getItems() {
        return Collections.unmodifiableList(items);
    }

    /** Returns total number of individual units across all line items. */
    public int getTotalItemCount() {
        return items.stream().mapToInt(OrderItem::getQuantity).sum();
    }

    @Override
    public String toString() {
        return String.format("Order{id='%s', customer='%s', items=%d, status=%s}",
                orderId, customer.getCustomerId(), items.size(), status);
    }
}
