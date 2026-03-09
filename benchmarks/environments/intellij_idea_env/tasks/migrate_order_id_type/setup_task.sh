#!/bin/bash
set -e
echo "=== Setting up migrate_order_id_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define project path
PROJECT_DIR="/home/ga/IdeaProjects/order-service"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/repository"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/controller"
mkdir -p "$PROJECT_DIR/src/test/java/com/ecommerce"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.ecommerce</groupId>
  <artifactId>order-service</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# 2. Create Order.java (The Target)
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/model/Order.java" << 'EOF'
package com.ecommerce.model;

import java.time.LocalDateTime;

public class Order {
    private int id;
    private String customerName;
    private double totalAmount;
    private LocalDateTime orderDate;

    public Order(int id, String customerName, double totalAmount) {
        this.id = id;
        this.customerName = customerName;
        this.totalAmount = totalAmount;
        this.orderDate = LocalDateTime.now();
    }

    public int getId() {
        return id;
    }

    public void setId(int id) {
        this.id = id;
    }

    public String getCustomerName() {
        return customerName;
    }

    public double getTotalAmount() {
        return totalAmount;
    }
}
EOF

# 3. Create OrderRepository.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/repository/OrderRepository.java" << 'EOF'
package com.ecommerce.repository;

import com.ecommerce.model.Order;
import java.util.HashMap;
import java.util.Map;

public class OrderRepository {
    private Map<Integer, Order> storage = new HashMap<>();

    public void save(Order order) {
        storage.put(order.getId(), order);
    }

    public Order findById(int id) {
        return storage.get(id);
    }
    
    public boolean exists(int id) {
        return storage.containsKey(id);
    }
}
EOF

# 4. Create OrderService.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/service/OrderService.java" << 'EOF'
package com.ecommerce.service;

import com.ecommerce.model.Order;
import com.ecommerce.repository.OrderRepository;

public class OrderService {
    private final OrderRepository repository;

    public OrderService(OrderRepository repository) {
        this.repository = repository;
    }

    public Order getOrderDetails(int orderId) {
        Order order = repository.findById(orderId);
        if (order == null) {
            throw new IllegalArgumentException("Order " + orderId + " not found");
        }
        return order;
    }

    public void createOrder(int id, String customer, double amount) {
        // ID generation logic would be here, but for now we accept explicit ID
        Order order = new Order(id, customer, amount);
        repository.save(order);
    }
}
EOF

# 5. Create OrderController.java (Simulated)
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/controller/OrderController.java" << 'EOF'
package com.ecommerce.controller;

import com.ecommerce.model.Order;
import com.ecommerce.service.OrderService;

public class OrderController {
    private final OrderService service;

    public OrderController(OrderService service) {
        this.service = service;
    }

    // GET /orders/{id}
    public String handleGetOrder(int id) {
        try {
            Order order = service.getOrderDetails(id);
            return "Order: " + order.getId() + ", Customer: " + order.getCustomerName();
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }
}
EOF

# 6. Create Unit Tests
cat > "$PROJECT_DIR/src/test/java/com/ecommerce/OrderServiceTest.java" << 'EOF'
package com.ecommerce;

import com.ecommerce.model.Order;
import com.ecommerce.repository.OrderRepository;
import com.ecommerce.service.OrderService;
import org.junit.Test;
import static org.junit.Assert.*;

public class OrderServiceTest {

    @Test
    public void testOrderFlow() {
        OrderRepository repo = new OrderRepository();
        OrderService service = new OrderService(repo);
        
        // Use a value that fits in int but will be migrated
        int testId = 100500; 
        
        service.createOrder(testId, "Test Customer", 99.99);
        
        Order retrieved = service.getOrderDetails(testId);
        assertEquals("Test Customer", retrieved.getCustomerName());
        assertEquals(testId, retrieved.getId());
    }
}
EOF

# Ensure permissions and ownership
chown -R ga:ga "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial file states
md5sum "$PROJECT_DIR/src/main/java/com/ecommerce/model/Order.java" > /tmp/initial_state_hash.txt

# Pre-compile to ensure project is valid
echo "Pre-compiling project..."
su - ga -c "cd $PROJECT_DIR && mvn clean compile -q"

# Launch IntelliJ and open the project
setup_intellij_project "$PROJECT_DIR" "order-service" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="