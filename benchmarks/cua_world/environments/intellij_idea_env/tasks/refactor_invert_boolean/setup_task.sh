#!/bin/bash
set -e
echo "=== Setting up Refactor Invert Boolean Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="order-processing-system"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/example/orders/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/orders/service"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/orders"

# 2. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example.orders</groupId>
  <artifactId>order-processing-system</artifactId>
  <packaging>jar</packaging>
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

# 3. Create Source Files

# Order.java (Target for refactoring)
cat > "$PROJECT_DIR/src/main/java/com/example/orders/model/Order.java" << 'EOF'
package com.example.orders.model;

import java.util.ArrayList;
import java.util.List;

public class Order {
    private String id;
    private double amount;
    // TODO: Refactor this negative logic to positive (valid)
    private boolean invalid;
    private List<String> items;

    public Order(String id, double amount) {
        this.id = id;
        this.amount = amount;
        this.invalid = false; // Default to valid
        this.items = new ArrayList<>();
    }

    public String getId() {
        return id;
    }

    public double getAmount() {
        return amount;
    }

    public boolean isInvalid() {
        return invalid;
    }

    public void setInvalid(boolean invalid) {
        this.invalid = invalid;
    }
    
    public void addItem(String item) {
        items.add(item);
    }
    
    public int getItemCount() {
        return items.size();
    }
    
    @Override
    public String toString() {
        return "Order{" + "id='" + id + '\'' + ", invalid=" + invalid + '}';
    }
}
EOF

# OrderValidator.java (Usage site 1)
cat > "$PROJECT_DIR/src/main/java/com/example/orders/service/OrderValidator.java" << 'EOF'
package com.example.orders.service;

import com.example.orders.model.Order;

public class OrderValidator {
    
    public boolean validate(Order order) {
        if (order == null) return false;
        
        // Complex logic using the negative flag
        if (order.isInvalid()) {
            System.out.println("Order " + order.getId() + " is explicitly marked as invalid");
            return false;
        }
        
        if (order.getAmount() < 0) {
            order.setInvalid(true);
            return false;
        }
        
        return !order.isInvalid();
    }
    
    public String getStatusMessage(Order order) {
        return order.isInvalid() ? "REJECTED" : "ACCEPTED";
    }
}
EOF

# OrderService.java (Usage site 2)
cat > "$PROJECT_DIR/src/main/java/com/example/orders/service/OrderService.java" << 'EOF'
package com.example.orders.service;

import com.example.orders.model.Order;

public class OrderService {
    private OrderValidator validator = new OrderValidator();
    
    public void processOrder(Order order) {
        // Double negative logic that we want to clean up
        if (!order.isInvalid()) {
            System.out.println("Processing valid order: " + order.getId());
            chargeCustomer(order);
        } else {
            System.out.println("Skipping invalid order: " + order.getId());
        }
    }
    
    public boolean isEligibleForDiscount(Order order) {
        // Only valid orders with amount > 100 get discount
        return !order.isInvalid() && order.getAmount() > 100.0;
    }
    
    private void chargeCustomer(Order order) {
        // dummy implementation
    }
}
EOF

# 4. Create Test Files
cat > "$PROJECT_DIR/src/test/java/com/example/orders/OrderTest.java" << 'EOF'
package com.example.orders;

import com.example.orders.model.Order;
import com.example.orders.service.OrderService;
import com.example.orders.service.OrderValidator;
import org.junit.Test;
import static org.junit.Assert.*;

public class OrderTest {

    @Test
    public void testDefaultOrderIsValid() {
        Order order = new Order("123", 50.0);
        // By default invalid should be false (so it is valid)
        assertFalse("New order should not be invalid", order.isInvalid());
    }

    @Test
    public void testSetInvalid() {
        Order order = new Order("123", 50.0);
        order.setInvalid(true);
        assertTrue(order.isInvalid());
    }

    @Test
    public void testValidatorAcceptsValidOrder() {
        Order order = new Order("123", 50.0);
        OrderValidator validator = new OrderValidator();
        assertTrue(validator.validate(order));
        assertEquals("ACCEPTED", validator.getStatusMessage(order));
    }

    @Test
    public void testValidatorRejectsInvalidOrder() {
        Order order = new Order("123", 50.0);
        order.setInvalid(true);
        OrderValidator validator = new OrderValidator();
        assertFalse(validator.validate(order));
        assertEquals("REJECTED", validator.getStatusMessage(order));
    }
    
    @Test
    public void testServiceDiscountLogic() {
        OrderService service = new OrderService();
        
        Order expensiveOrder = new Order("999", 200.0);
        // expensive and valid -> eligible
        assertTrue(service.isEligibleForDiscount(expensiveOrder));
        
        Order invalidExpensive = new Order("888", 200.0);
        invalidExpensive.setInvalid(true);
        // expensive but invalid -> not eligible
        assertFalse(service.isEligibleForDiscount(invalidExpensive));
    }
    
    @Test
    public void testNegativeAmountMarksInvalid() {
        Order order = new Order("NEG", -10.0);
        OrderValidator validator = new OrderValidator();
        
        // Validator should detect neg amount and mark invalid
        assertFalse(validator.validate(order));
        assertTrue("Order should have been marked invalid by validator", order.isInvalid());
    }
}
EOF

# 5. Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 6. Record checksums of initial state
md5sum "$PROJECT_DIR/src/main/java/com/example/orders/model/Order.java" > /tmp/initial_order_hash.txt

# 7. Open Project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "order-processing-system"

# 8. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="