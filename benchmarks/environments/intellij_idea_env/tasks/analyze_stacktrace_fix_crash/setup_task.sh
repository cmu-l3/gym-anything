#!/bin/bash
set -e
echo "=== Setting up analyze_stacktrace_fix_crash task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/ecommerce-legacy"
LOG_FILE="/home/ga/Desktop/crash_log.txt"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/core"
mkdir -p "$PROJECT_DIR/src/test/java/com/ecommerce/core"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.ecommerce</groupId>
    <artifactId>ecommerce-legacy</artifactId>
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
POMEOF

# 2. Create Domain Classes
# Address.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/core/Address.java" << 'EOF'
package com.ecommerce.core;

public class Address {
    private String street;
    private String city;
    private String zipCode;

    public Address(String street, String city, String zipCode) {
        this.street = street;
        this.city = city;
        this.zipCode = zipCode;
    }

    public String getCity() { return city; }
    public String getZipCode() { return zipCode; }
}
EOF

# Customer.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/core/Customer.java" << 'EOF'
package com.ecommerce.core;

public class Customer {
    private String id;
    private String name;
    private Address billingAddress;

    public Customer(String id, String name, Address billingAddress) {
        this.id = id;
        this.name = name;
        this.billingAddress = billingAddress;
    }

    public Address getBillingAddress() { return billingAddress; }
    public String getName() { return name; }
}
EOF

# Order.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/core/Order.java" << 'EOF'
package com.ecommerce.core;

public class Order {
    private String orderId;
    private Customer customer;
    private double amount;

    public Order(String orderId, Customer customer, double amount) {
        this.orderId = orderId;
        this.customer = customer;
        this.amount = amount;
    }

    public Customer getCustomer() { return customer; }
    public String getOrderId() { return orderId; }
}
EOF

# 3. Create the Service with the Bug (buried in lines)
# We calculate lines precisely to match the stack trace
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java" << 'EOF'
package com.ecommerce.core;

import java.util.logging.Logger;

public class OrderProcessingService {
    private static final Logger LOGGER = Logger.getLogger(OrderProcessingService.class.getName());

    public void processOrder(Order order) {
        LOGGER.info("Starting processing for order: " + order.getOrderId());
        
        validateOrder(order);
        checkInventory(order);
        
        // Processing pipeline steps...
EOF

# Append 80 lines of filler methods to push the bug down to line ~96
for i in {1..80}; do
    echo "        step$i();" >> "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java"
done

cat >> "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java" << 'EOF'
        
        completeProcessing(order);
    }

    /*
     * Calculates tax based on the billing address city.
     * Legacy tax calculation engine.
     */
    private double calculateTax(Order order) {
        double taxRate = 0.05;
        
        // BUG IS HERE (Line 104 approx based on header + 80 filler + method start)
        // If customer has no billing address, this throws NPE
        String city = order.getCustomer().getBillingAddress().getCity();
        
        if (city.equalsIgnoreCase("New York")) {
            taxRate = 0.08;
        } else if (city.equalsIgnoreCase("California")) {
            taxRate = 0.09;
        }
        
        return taxRate;
    }

    private void validateOrder(Order order) {
        if (order == null) throw new IllegalArgumentException("Order cannot be null");
    }

    private void checkInventory(Order order) {
        // Mock inventory check
    }
    
    public void completeProcessing(Order order) {
        double tax = calculateTax(order);
        LOGGER.info("Tax calculated: " + tax);
    }
EOF

# Generate filler method definitions
for i in {1..80}; do
    echo "    private void step$i() { /* verification step $i */ }" >> "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java"
done

echo "}" >> "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java"


# 4. Generate the Stack Trace
# The file structure above puts 'calculateTax' call roughly at line 105.
# Let's check line count to be sure for the stack trace.
# Header (9 lines) + Loop (80 lines) + Context (9 lines) + Bug Line = 9 + 80 + 9 + 1 = 99?
# Let's count properly:
# 1-8: package + imports + class + vars
# 9: processOrder start
# 10-12: logger + validate + check
# 13-92: step1..80 calls
# 93: blank
# 94: completeProcessing call
# 95: }
# 96-100: calculateTax signature + taxRate
# 101: blank
# 102: comment
# 103: comment
# 104: String city = ... <-- THE BUG
BUG_LINE=104

# Generate the log file with correct line numbers
cat > "$LOG_FILE" << LOGEOF
Exception in thread "main" java.lang.NullPointerException: Cannot invoke "com.ecommerce.core.Address.getCity()" because the return value of "com.ecommerce.core.Customer.getBillingAddress()" is null
	at com.ecommerce.core.OrderProcessingService.calculateTax(OrderProcessingService.java:$BUG_LINE)
	at com.ecommerce.core.OrderProcessingService.completeProcessing(OrderProcessingService.java:115)
	at com.ecommerce.core.OrderProcessingService.processOrder(OrderProcessingService.java:94)
	at com.ecommerce.core.App.main(App.java:15)
LOGEOF

chown -R ga:ga "$PROJECT_DIR"
chown ga:ga "$LOG_FILE"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open IntelliJ project
setup_intellij_project "$PROJECT_DIR" "ecommerce-legacy" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="