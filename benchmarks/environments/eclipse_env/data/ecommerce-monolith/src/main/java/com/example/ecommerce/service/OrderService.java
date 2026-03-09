package com.example.ecommerce.service;

import com.example.ecommerce.model.Order;
import com.example.ecommerce.model.OrderItem;
import com.example.ecommerce.model.Product;
import com.example.ecommerce.repository.OrderRepository;
import com.example.ecommerce.repository.ProductRepository;
import com.example.ecommerce.repository.CustomerRepository;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public class OrderService {

    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;
    private final CustomerRepository customerRepository;

    public OrderService(OrderRepository orderRepository,
                         ProductRepository productRepository,
                         CustomerRepository customerRepository) {
        this.orderRepository = orderRepository;
        this.productRepository = productRepository;
        this.customerRepository = customerRepository;
    }

    public Order placeOrder(int customerId, List<int[]> productQuantityPairs) {
        customerRepository.findById(customerId)
            .orElseThrow(() -> new IllegalArgumentException("Customer not found: " + customerId));

        Order order = new Order(0, customerId, LocalDateTime.now(), "PENDING",
            BigDecimal.ZERO, "");
        BigDecimal total = BigDecimal.ZERO;

        for (int[] pq : productQuantityPairs) {
            int productId = pq[0];
            int quantity = pq[1];
            Product product = productRepository.findById(productId)
                .orElseThrow(() -> new IllegalArgumentException("Product not found: " + productId));
            if (product.getStockQuantity() < quantity)
                throw new IllegalStateException("Insufficient stock for: " + product.getName());

            OrderItem item = new OrderItem(0, 0, productId, quantity, product.getPrice());
            order.addItem(item);
            total = total.add(product.getPrice().multiply(BigDecimal.valueOf(quantity)));
        }

        order.setTotalAmount(total);
        return orderRepository.save(order);
    }

    public Optional<Order> getOrder(int id) {
        return orderRepository.findById(id);
    }

    public List<Order> getCustomerOrders(int customerId) {
        return orderRepository.findByCustomerId(customerId);
    }

    public Order updateStatus(int orderId, String status) {
        Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> new IllegalArgumentException("Order not found: " + orderId));
        order.setStatus(status);
        return orderRepository.save(order);
    }
}
