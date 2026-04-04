#!/bin/bash
set -e
echo "=== Setting up refactor_introduce_parameter_object task ==="

source /workspace/scripts/task_utils.sh

# Define project path
PROJECT_DIR="/home/ga/IdeaProjects/legacy-payment-module"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/payments"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/payments"

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>legacy-payment-module</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>legacy-payment-module</name>
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

# Create PaymentProcessor.java (The Target)
cat > "$PROJECT_DIR/src/main/java/com/example/payments/PaymentProcessor.java" << 'JAVAEOF'
package com.example.payments;

public class PaymentProcessor {
    
    public void processTransaction(String merchantId, double amount, String currency, String cardNum, String cvv, String expiry, String note) {
        System.out.println("Processing transaction for merchant: " + merchantId);
        System.out.println("Amount: " + amount + " " + currency);
        // Simulated processing logic
        if (amount <= 0) {
            throw new IllegalArgumentException("Invalid amount");
        }
    }
}
JAVAEOF

# Create App.java (Caller 1)
cat > "$PROJECT_DIR/src/main/java/com/example/payments/App.java" << 'JAVAEOF'
package com.example.payments;

public class App {
    public static void main(String[] args) {
        PaymentProcessor processor = new PaymentProcessor();
        processor.processTransaction("MCH-12345", 99.99, "USD", "4111222233334444", "123", "12/25", "E-commerce purchase");
    }
}
JAVAEOF

# Create PaymentServiceTest.java (Caller 2 - Test)
cat > "$PROJECT_DIR/src/test/java/com/example/payments/PaymentServiceTest.java" << 'JAVAEOF'
package com.example.payments;

import org.junit.Test;
import static org.junit.Assert.*;

public class PaymentServiceTest {
    
    @Test
    public void testProcessTransaction() {
        PaymentProcessor processor = new PaymentProcessor();
        try {
            processor.processTransaction("TEST-MCH", 50.0, "EUR", "4242424242424242", "999", "01/30", "Test transaction");
        } catch (Exception e) {
            fail("Should not throw exception: " + e.getMessage());
        }
    }
}
JAVAEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Initial Checksum to detect changes later
md5sum "$PROJECT_DIR/src/main/java/com/example/payments/PaymentProcessor.java" > /tmp/initial_checksum.txt

# Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "legacy-payment-module" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="