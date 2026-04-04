package com.example.ecommerce.service;

import com.example.ecommerce.model.Customer;
import com.example.ecommerce.repository.CustomerRepository;

import java.util.List;
import java.util.Optional;

public class CustomerService {

    private final CustomerRepository customerRepository;

    public CustomerService(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    public Customer registerCustomer(String firstName, String lastName, String email,
                                      String phone, String shippingAddress) {
        if (email == null || !email.contains("@"))
            throw new IllegalArgumentException("Invalid email");
        customerRepository.findByEmail(email).ifPresent(c -> {
            throw new IllegalStateException("Email already registered: " + email);
        });
        return customerRepository.save(
            new Customer(0, firstName, lastName, email, phone, shippingAddress));
    }

    public Optional<Customer> getCustomer(int id) {
        return customerRepository.findById(id);
    }

    public List<Customer> getAllCustomers() {
        return customerRepository.findAll();
    }
}
