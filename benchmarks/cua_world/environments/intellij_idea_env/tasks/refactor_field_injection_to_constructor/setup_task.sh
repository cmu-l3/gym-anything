#!/bin/bash
set -e
echo "=== Setting up refactor_field_injection_to_constructor task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="legacy-orders"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Create Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/example/orders/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/orders/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/orders/service"

# 2. Create POM.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>legacy-orders</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <!-- Spring Context for @Service, @Autowired -->
    <dependency>
      <groupId>org.springframework</groupId>
      <artifactId>spring-context</artifactId>
      <version>6.0.11</version>
    </dependency>
    <!-- JUnit 5 -->
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-api</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-engine</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
    <!-- Mockito -->
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
      <version>5.3.1</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-junit-jupiter</artifactId>
      <version>5.3.1</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POMEOF

# 3. Create Supporting Classes
# Model
cat > "$PROJECT_DIR/src/main/java/com/example/orders/model/Order.java" << 'EOF'
package com.example.orders.model;
public class Order {
    private String id;
    public String getId() { return id; }
}
EOF

# Dependencies
for SERVICE in InventoryService PaymentGateway NotificationService; do
cat > "$PROJECT_DIR/src/main/java/com/example/orders/service/${SERVICE}.java" << EOF
package com.example.orders.service;
import org.springframework.stereotype.Service;
import com.example.orders.model.Order;

@Service
public class ${SERVICE} {
    public void process(Order order) {
        System.out.println("${SERVICE} processing " + order);
    }
}
EOF
done

# 4. Create the Target Class (with Field Injection)
cat > "$PROJECT_DIR/src/main/java/com/example/orders/service/OrderProcessingService.java" << 'EOF'
package com.example.orders.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.example.orders.model.Order;

@Service
public class OrderProcessingService {

    @Autowired
    private InventoryService inventoryService;

    @Autowired
    private PaymentGateway paymentGateway;

    @Autowired
    private NotificationService notificationService;

    public void processOrder(Order order) {
        System.out.println("Processing order...");
        inventoryService.process(order);
        paymentGateway.process(order);
        notificationService.process(order);
        System.out.println("Order processed.");
    }
}
EOF

# 5. Create the Test Class
cat > "$PROJECT_DIR/src/test/java/com/example/orders/service/OrderProcessingServiceTest.java" << 'EOF'
package com.example.orders.service;

import com.example.orders.model.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class OrderProcessingServiceTest {

    @Mock
    private InventoryService inventoryService;

    @Mock
    private PaymentGateway paymentGateway;

    @Mock
    private NotificationService notificationService;

    @InjectMocks
    private OrderProcessingService orderProcessingService;

    @Test
    void testProcessOrder() {
        Order order = new Order();
        orderProcessingService.processOrder(order);

        verify(inventoryService).process(any(Order.class));
        verify(paymentGateway).process(any(Order.class));
        verify(notificationService).process(any(Order.class));
    }
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record initial state
md5sum "$PROJECT_DIR/src/main/java/com/example/orders/service/OrderProcessingService.java" > /tmp/initial_hash.txt
date +%s > /tmp/task_start_time.txt

# Open in IntelliJ
setup_intellij_project "$PROJECT_DIR" "legacy-orders" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="