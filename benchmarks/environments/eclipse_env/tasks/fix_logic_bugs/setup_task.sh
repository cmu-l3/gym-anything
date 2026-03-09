#!/bin/bash
set -e
echo "=== Setting up fix_logic_bugs task ==="

source /workspace/scripts/task_utils.sh

# Define paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="EcommerceBackend"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"
HIDDEN_DIR="/var/lib/task_hidden/tests"

# 1. Create Project Structure
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/services"
mkdir -p "$PROJECT_DIR/src/test/java/com/ecommerce/services"
mkdir -p "$HIDDEN_DIR"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.ecommerce</groupId>
  <artifactId>backend</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
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
  </dependencies>
</project>
EOFPOM

# 3. Create Buggy Service Class
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/services/OrderService.java" << 'EOFJAVA'
package com.ecommerce.services;

public class OrderService {
    
    /**
     * Calculates final total including tax, shipping, and discounts.
     */
    public double calculateTotal(double subtotal, String stateCode) {
        double discount = calculateDiscount(subtotal);
        double shipping = calculateShipping(subtotal);
        double tax = calculateTax(subtotal - discount, stateCode);
        
        return (subtotal - discount) + shipping + tax;
    }

    private double calculateDiscount(double subtotal) {
        // Logic: Orders > 500 get 5% off
        if (subtotal > 500.0) {
            int discountPercent = 5;
            // BUG 1: Integer division. 5/100 is 0.
            return subtotal * (discountPercent / 100); 
        }
        return 0.0;
    }

    private double calculateShipping(double subtotal) {
        // Logic: Free shipping for orders of $100 or more
        // BUG 2: Exact boundary error. Should be >= 100.00
        if (subtotal > 100.00) {
            return 0.0;
        }
        return 9.99; // Standard shipping
    }

    private double calculateTax(double taxableAmount, String stateCode) {
        double taxRate = 0.0;
        
        switch (stateCode) {
            case "NY":
                taxRate = 0.088; // 8.8%
                break;
            case "CA":
                taxRate = 0.075; // 7.5%
                break;
            case "NJ":
                taxRate = 0.066; // 6.6%
                // BUG 3: Missing break! Falls through to Default
            default:
                taxRate = 0.05; // 5% default national tax
        }
        
        return taxableAmount * taxRate;
    }
}
EOFJAVA

# 4. Create Visible Tests
cat > "$PROJECT_DIR/src/test/java/com/ecommerce/services/OrderServiceTest.java" << 'EOFTEST'
package com.ecommerce.services;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

public class OrderServiceTest {

    private OrderService service = new OrderService();

    @Test
    public void testBulkDiscount() {
        // Order of 1000. Should get 5% discount ($50 off) -> 950
        // Shipping: Free (>100).
        // Tax (Default 5% of 950): 47.5
        // Total: 997.5
        double total = service.calculateTotal(1000.0, "TX");
        assertEquals(997.5, total, 0.01, "Discount should apply for orders > 500");
    }

    @Test
    public void testShippingThreshold() {
        // Order of 100 exactly. Should be free shipping.
        // Tax (Default 5%): 5.0
        // Total: 105.0
        double total = service.calculateTotal(100.0, "TX");
        assertEquals(105.0, total, 0.01, "Shipping should be free for exactly $100");
    }

    @Test
    public void testTaxNJ() {
        // Order of 100. Free shipping.
        // Tax NJ: 6.6% of 100 = 6.60
        // Total: 106.60
        double total = service.calculateTotal(100.0, "NJ");
        assertEquals(106.60, total, 0.01, "NJ tax should be 6.6%");
    }
}
EOFTEST

# 5. Create Hidden Tests (Stored securely, injected later)
cat > "$HIDDEN_DIR/OrderServiceHiddenTest.java" << 'EOFHIDDEN'
package com.ecommerce.services;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

public class OrderServiceHiddenTest {
    
    private OrderService service = new OrderService();

    @Test
    public void testBulkDiscount_CalculatesCorrectly() {
        // Hidden value: 600. Discount 5% = 30. Subtotal = 570.
        // Tax (Default 5% of 570) = 28.5
        // Total = 598.5
        double total = service.calculateTotal(600.0, "NV");
        assertEquals(598.5, total, 0.01, "Hidden Test: Discount logic failed");
    }

    @Test
    public void testFreeShipping_ExactThreshold() {
        // Retesting the exact boundary with a different state
        // 100.0, Default tax 5% -> 5.0
        // Total 105.0
        double total = service.calculateTotal(100.0, "XX");
        assertEquals(105.0, total, 0.01, "Hidden Test: Shipping boundary failed");
    }

    @Test
    public void testTax_NJ() {
        // Test NJ with non-shipping, non-discount amount
        // 50.0. Shipping 9.99.
        // Tax 6.6% of 50 = 3.30
        // Total = 50 + 9.99 + 3.30 = 63.29
        double total = service.calculateTotal(50.0, "NJ");
        assertEquals(63.29, total, 0.01, "Hidden Test: NJ Tax logic failed");
    }
}
EOFHIDDEN

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod -R 700 "$HIDDEN_DIR" # Only root can read hidden tests until export time

# Record start time
date +%s > /tmp/task_start_time.txt

# Create .project/.classpath files to make it Eclipse-ready immediately
# This helps avoiding the "Import" step if we wanted, but we'll stick to instructions
# calling for Import to be realistic. However, pre-generating metadata makes Import faster.
cd "$PROJECT_DIR"
su - ga -c "mvn eclipse:eclipse -DdownloadSources=true -DdownloadJavadocs=true > /dev/null 2>&1" || true

# Pre-download dependencies
su - ga -c "mvn dependency:go-offline > /dev/null 2>&1" || true

# Setup Eclipse
source /workspace/scripts/setup_eclipse.sh

# Wait for Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Maximize
focus_eclipse_window
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="