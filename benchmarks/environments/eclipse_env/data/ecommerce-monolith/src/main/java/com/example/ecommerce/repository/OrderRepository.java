package com.example.ecommerce.repository;

import com.example.ecommerce.model.Order;

import java.util.*;

public class OrderRepository {
    private final Map<Integer, Order> store = new HashMap<>();
    private int nextId = 1;

    public Order save(Order order) {
        if (order.getId() == 0) {
            order.setId(nextId++);
        }
        store.put(order.getId(), order);
        return order;
    }

    public Optional<Order> findById(int id) {
        return Optional.ofNullable(store.get(id));
    }

    public List<Order> findByCustomerId(int customerId) {
        List<Order> result = new ArrayList<>();
        for (Order o : store.values()) {
            if (o.getCustomerId() == customerId) result.add(o);
        }
        return result;
    }

    public List<Order> findAll() {
        return new ArrayList<>(store.values());
    }

    public boolean delete(int id) {
        return store.remove(id) != null;
    }
}
