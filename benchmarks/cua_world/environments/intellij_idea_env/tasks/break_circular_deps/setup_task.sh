#!/bin/bash
set -e
echo "=== Setting up break_circular_deps task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/order-management"
mkdir -p "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# Generate Project Files (Simulating an existing codebase with issues)
# ==============================================================================

# 1. POM.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>order-management</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.12</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POMEOF

# Create package directories
mkdir -p "$PROJECT_DIR/src/main/java/com/example/order/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/order/service"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/order/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/order/service"

# 2. LineItem.java (Clean model)
cat > "$PROJECT_DIR/src/main/java/com/example/order/model/LineItem.java" << 'EOF'
package com.example.order.model;

public class LineItem {
    private String productName;
    private double price;
    private int quantity;

    public LineItem(String productName, double price, int quantity) {
        this.productName = productName;
        this.price = price;
        this.quantity = quantity;
    }

    public double getTotal() {
        return price * quantity;
    }

    public String getProductName() { return productName; }
    public double getPrice() { return price; }
    public int getQuantity() { return quantity; }
}
EOF

# 3. Customer.java (Problematic: depends on FormattingService)
cat > "$PROJECT_DIR/src/main/java/com/example/order/model/Customer.java" << 'EOF'
package com.example.order.model;

import com.example.order.service.FormattingService; // CIRCULAR DEPENDENCY

public class Customer {
    private String firstName;
    private String lastName;
    private String email;
    private String tier; // "GOLD", "SILVER", "BRONZE"

    public Customer(String firstName, String lastName, String email, String tier) {
        this.firstName = firstName;
        this.lastName = lastName;
        this.email = email;
        this.tier = tier;
    }

    public String getFirstName() { return firstName; }
    public String getLastName() { return lastName; }
    public String getEmail() { return email; }
    public String getTier() { return tier; }

    public String getDisplayName() {
        // Bad: Model calls Service
        return FormattingService.formatFullName(this);
    }
}
EOF

# 4. Order.java (Problematic: depends on DiscountService)
cat > "$PROJECT_DIR/src/main/java/com/example/order/model/Order.java" << 'EOF'
package com.example.order.model;

import com.example.order.service.DiscountService; // CIRCULAR DEPENDENCY
import java.util.ArrayList;
import java.util.List;

public class Order {
    private String orderId;
    private Customer customer;
    private List<LineItem> items = new ArrayList<>();
    private String discountCode;

    public Order(String orderId, Customer customer) {
        this.orderId = orderId;
        this.customer = customer;
    }

    public void addItem(LineItem item) {
        items.add(item);
    }

    public void setDiscountCode(String code) {
        this.discountCode = code;
    }

    public String getDiscountCode() {
        return discountCode;
    }

    public Customer getCustomer() {
        return customer;
    }

    public double getSubtotal() {
        return items.stream().mapToDouble(LineItem::getTotal).sum();
    }

    public double getTotalWithDiscount() {
        double subtotal = getSubtotal();
        // Bad: Model calls Service
        double discount = DiscountService.calculateDiscount(this);
        return subtotal - discount;
    }
}
EOF

# 5. FormattingService.java (Service)
cat > "$PROJECT_DIR/src/main/java/com/example/order/service/FormattingService.java" << 'EOF'
package com.example.order.service;

import com.example.order.model.Customer;

public class FormattingService {
    public static String formatFullName(Customer customer) {
        if (customer == null) return "Unknown";
        return customer.getLastName() + ", " + customer.getFirstName();
    }
    
    public String formatEmail(Customer customer) {
        return customer.getFirstName().toLowerCase() + "." + customer.getLastName().toLowerCase() + "@example.com";
    }
}
EOF

# 6. DiscountService.java (Service)
cat > "$PROJECT_DIR/src/main/java/com/example/order/service/DiscountService.java" << 'EOF'
package com.example.order.service;

import com.example.order.model.Order;
import com.example.order.model.Customer;

public class DiscountService {
    
    public static double calculateDiscount(Order order) {
        if (order == null) return 0.0;
        
        double subtotal = order.getSubtotal();
        String code = order.getDiscountCode();
        Customer customer = order.getCustomer();
        
        double discount = 0.0;
        
        // Code-based discount
        if ("SAVE10".equals(code)) {
            discount += 10.0;
        }
        
        // Tier-based percentage discount
        if (customer != null && "GOLD".equals(customer.getTier())) {
            discount += subtotal * 0.10; // 10% off for Gold
        } else if (customer != null && "SILVER".equals(customer.getTier())) {
            discount += subtotal * 0.05; // 5% off for Silver
        }
        
        // Don't exceed subtotal
        if (discount > subtotal) {
            discount = subtotal;
        }
        
        return discount;
    }
}
EOF

# 7. App.java (Main entry)
cat > "$PROJECT_DIR/src/main/java/com/example/order/App.java" << 'EOF'
package com.example.order;

import com.example.order.model.Customer;
import com.example.order.model.Order;
import com.example.order.model.LineItem;

public class App {
    public static void main(String[] args) {
        Customer c = new Customer("John", "Doe", "john@test.com", "GOLD");
        Order o = new Order("ORD-1", c);
        o.addItem(new LineItem("Widget", 100.0, 2));
        o.setDiscountCode("SAVE10");
        
        System.out.println("Customer: " + c.getDisplayName());
        System.out.println("Total: " + o.getTotalWithDiscount());
    }
}
EOF

# ==============================================================================
# Generate Tests (Must pass before and after)
# ==============================================================================

# 8. OrderTest.java
cat > "$PROJECT_DIR/src/test/java/com/example/order/model/OrderTest.java" << 'EOF'
package com.example.order.model;

import org.junit.Test;
import static org.junit.Assert.*;

public class OrderTest {

    @Test
    public void testSubtotal() {
        Customer c = new Customer("Test", "User", "test@example.com", "BRONZE");
        Order o = new Order("1", c);
        o.addItem(new LineItem("Item1", 10.0, 2));
        o.addItem(new LineItem("Item2", 5.0, 1));
        assertEquals(25.0, o.getSubtotal(), 0.001);
    }

    @Test
    public void testTotalWithDiscount_GoldTier() {
        Customer c = new Customer("Test", "User", "test@example.com", "GOLD");
        Order o = new Order("1", c);
        o.addItem(new LineItem("Item1", 100.0, 1));
        // Gold gets 10% off -> 10.0 discount. Total = 90.0
        assertEquals(90.0, o.getTotalWithDiscount(), 0.001);
    }
    
    @Test
    public void testTotalWithDiscount_CodeAndTier() {
        Customer c = new Customer("Test", "User", "test@example.com", "GOLD");
        Order o = new Order("1", c);
        o.addItem(new LineItem("Item1", 100.0, 1));
        o.setDiscountCode("SAVE10");
        // Gold 10% (10.0) + Code (10.0) = 20.0 discount. Total = 80.0
        assertEquals(80.0, o.getTotalWithDiscount(), 0.001);
    }
}
EOF

# 9. CustomerTest.java
cat > "$PROJECT_DIR/src/test/java/com/example/order/model/CustomerTest.java" << 'EOF'
package com.example.order.model;

import org.junit.Test;
import static org.junit.Assert.*;

public class CustomerTest {
    @Test
    public void testDisplayName() {
        Customer c = new Customer("Jane", "Smith", "jane@test.com", "SILVER");
        assertEquals("Smith, Jane", c.getDisplayName());
    }
}
EOF

# 10. DiscountServiceTest.java
cat > "$PROJECT_DIR/src/test/java/com/example/order/service/DiscountServiceTest.java" << 'EOF'
package com.example.order.service;

import com.example.order.model.Customer;
import com.example.order.model.Order;
import com.example.order.model.LineItem;
import org.junit.Test;
import static org.junit.Assert.*;

public class DiscountServiceTest {
    @Test
    public void testCalculateDiscount_Silver() {
        Customer c = new Customer("S", "Tier", "s@t.com", "SILVER");
        Order o = new Order("2", c);
        o.addItem(new LineItem("Item", 200.0, 1));
        // Silver 5% = 10.0
        assertEquals(10.0, DiscountService.calculateDiscount(o), 0.001);
    }
    
    @Test
    public void testCalculateDiscount_NoDiscount() {
        Customer c = new Customer("B", "Tier", "b@t.com", "BRONZE");
        Order o = new Order("3", c);
        o.addItem(new LineItem("Item", 100.0, 1));
        assertEquals(0.0, DiscountService.calculateDiscount(o), 0.001);
    }
}
EOF

# 11. FormattingServiceTest.java
cat > "$PROJECT_DIR/src/test/java/com/example/order/service/FormattingServiceTest.java" << 'EOF'
package com.example.order.service;

import com.example.order.model.Customer;
import org.junit.Test;
import static org.junit.Assert.*;

public class FormattingServiceTest {
    @Test
    public void testFormatFullName() {
        Customer c = new Customer("Bob", "Builder", "bob@build.com", "GOLD");
        assertEquals("Builder, Bob", FormattingService.formatFullName(c));
    }
    
    @Test
    public void testFormatEmail() {
        FormattingService fs = new FormattingService();
        Customer c = new Customer("Bob", "Builder", "bob@build.com", "GOLD");
        assertEquals("bob.builder@example.com", fs.formatEmail(c));
    }
}
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-warm Maven (download dependencies)
echo "Pre-warming Maven..."
su - ga -c "cd $PROJECT_DIR && mvn clean compile test -DskipTests"

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "order-management" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="