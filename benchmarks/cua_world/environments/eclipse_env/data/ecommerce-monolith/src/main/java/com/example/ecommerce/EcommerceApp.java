package com.example.ecommerce;

import com.example.ecommerce.repository.*;
import com.example.ecommerce.service.*;
import com.example.ecommerce.model.*;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;

public class EcommerceApp {

    public static void main(String[] args) {
        ProductRepository productRepo = new ProductRepository();
        CustomerRepository customerRepo = new CustomerRepository();
        OrderRepository orderRepo = new OrderRepository();

        ProductService productService = new ProductService(productRepo);
        CustomerService customerService = new CustomerService(customerRepo);
        OrderService orderService = new OrderService(orderRepo, productRepo, customerRepo);

        System.out.println("E-commerce Application");
        System.out.println("Products: " + productService.getAllProducts().size());
        System.out.println("Customers: " + customerService.getAllCustomers().size());
    }
}
