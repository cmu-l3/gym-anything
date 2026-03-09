package com.example.ecommerce.repository;

import com.example.ecommerce.model.Customer;

import java.util.*;

public class CustomerRepository {
    private final Map<Integer, Customer> store = new HashMap<>();
    private int nextId = 1;

    public CustomerRepository() {
        save(new Customer(0, "Alice", "Thompson", "alice@example.com", "555-0101", "123 Maple St"));
        save(new Customer(0, "Bob", "Martinez", "bob@example.com", "555-0102", "456 Oak Ave"));
        save(new Customer(0, "Carol", "White", "carol@example.com", "555-0103", "789 Pine Rd"));
    }

    public Customer save(Customer customer) {
        if (customer.getId() == 0) {
            customer.setId(nextId++);
        }
        store.put(customer.getId(), customer);
        return customer;
    }

    public Optional<Customer> findById(int id) {
        return Optional.ofNullable(store.get(id));
    }

    public Optional<Customer> findByEmail(String email) {
        return store.values().stream().filter(c -> c.getEmail().equals(email)).findFirst();
    }

    public List<Customer> findAll() {
        return new ArrayList<>(store.values());
    }
}
