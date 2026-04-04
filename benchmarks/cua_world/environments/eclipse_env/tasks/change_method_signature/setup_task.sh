#!/bin/bash
echo "=== Setting up change_method_signature task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define project path
PROJECT_DIR="/home/ga/eclipse-workspace/PaymentPlatform"
SRC_DIR="$PROJECT_DIR/src/main/java/com/acme/payment"
TEST_DIR="$PROJECT_DIR/src/test/java/com/acme/payment"

# Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$SRC_DIR/model"
mkdir -p "$TEST_DIR"

# 1. Create Maven POM
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.acme</groupId>
  <artifactId>payment-platform</artifactId>
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
EOFPOM

# 2. Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>PaymentPlatform</name>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOFPROJECT

# 3. Create Eclipse .classpath
cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOFCLASSPATH

# 4. Create Source Files

# Model: PaymentResult
cat > "$SRC_DIR/model/PaymentResult.java" << 'EOF'
package com.acme.payment.model;
public enum PaymentResult { SUCCESS, FAILED, PENDING }
EOF

# Model: Transaction
cat > "$SRC_DIR/model/Transaction.java" << 'EOF'
package com.acme.payment.model;
public class Transaction {
    private String id;
    private double amount;
    public Transaction(String id, double amount) { this.id = id; this.amount = amount; }
    public String getId() { return id; }
    public double getAmount() { return amount; }
}
EOF

# Service: PaymentService (TARGET FOR REFACTORING)
cat > "$SRC_DIR/PaymentService.java" << 'EOF'
package com.acme.payment;
import com.acme.payment.model.PaymentResult;

public class PaymentService {
    
    /**
     * Processes a payment for a specific customer.
     * TODO: Add currency and priority support
     */
    public PaymentResult processPayment(String customerId, double amount) {
        System.out.println("Processing payment for " + customerId + ": " + amount);
        if (amount <= 0) return PaymentResult.FAILED;
        return PaymentResult.SUCCESS;
    }
    
    public void validateCustomer(String customerId) {
        // Validation logic
    }
}
EOF

# Caller 1: OrderProcessor
cat > "$SRC_DIR/OrderProcessor.java" << 'EOF'
package com.acme.payment;
import com.acme.payment.model.PaymentResult;

public class OrderProcessor {
    private PaymentService paymentService = new PaymentService();
    
    public void processOrder(String orderId) {
        // Call site 1
        paymentService.processPayment("CUST-001", 99.99);
    }
    
    public void retryOrder(String orderId) {
        // Call site 2
        paymentService.processPayment("CUST-001", 99.99);
    }
    
    public void expressOrder() {
        // Call site 3
        PaymentResult result = paymentService.processPayment("CUST-VIP", 500.00);
    }
}
EOF

# Caller 2: SubscriptionManager
cat > "$SRC_DIR/SubscriptionManager.java" << 'EOF'
package com.acme.payment;

public class SubscriptionManager {
    private PaymentService service;
    
    public SubscriptionManager() {
        this.service = new PaymentService();
    }
    
    public void renewSubscription(String subId) {
        // Call site 4
        service.processPayment("SUB-" + subId, 19.99);
    }
    
    public void upgradeSubscription() {
        // Call site 5
        service.processPayment("SUB-UPGRADE", 29.99);
    }
    
    public void chargeLateFee() {
        // Call site 6
        service.processPayment("LATE-FEE", 5.00);
    }
}
EOF

# Caller 3: RefundHandler
cat > "$SRC_DIR/RefundHandler.java" << 'EOF'
package com.acme.payment;

public class RefundHandler {
    public void processReverseCharge() {
        PaymentService ps = new PaymentService();
        // Call site 7
        ps.processPayment("REV-001", -50.00);
        
        // Call site 8
        ps.processPayment("REV-002", -10.00);
    }
}
EOF

# Caller 4: BatchProcessor
cat > "$SRC_DIR/BatchProcessor.java" << 'EOF'
package com.acme.payment;

public class BatchProcessor {
    public void runBatch() {
        PaymentService svc = new PaymentService();
        for(int i=0; i<3; i++) {
            // Call sites 9, 10, 11 (in loop concept)
            svc.processPayment("BATCH-" + i, 100.0 * i);
        }
    }
}
EOF

# Caller 5: CheckoutController
cat > "$SRC_DIR/CheckoutController.java" << 'EOF'
package com.acme.payment;

public class CheckoutController {
    public void doCheckout() {
        PaymentService s = new PaymentService();
        // Call site 12
        s.processPayment("GUEST", 45.50);
        // Call site 13
        s.processPayment("MEMBER", 40.50);
    }
}
EOF

# Caller 6: Main
cat > "$SRC_DIR/Main.java" << 'EOF'
package com.acme.payment;

public class Main {
    public static void main(String[] args) {
        PaymentService ps = new PaymentService();
        // Call site 14
        ps.processPayment("MAIN-TEST", 1.00);
    }
}
EOF

# Caller 7: Test Class
cat > "$TEST_DIR/PaymentServiceTest.java" << 'EOF'
package com.acme.payment;
import org.junit.Test;
import static org.junit.Assert.*;
import com.acme.payment.model.PaymentResult;

public class PaymentServiceTest {
    @Test
    public void testProcess() {
        PaymentService ps = new PaymentService();
        // Call site 15
        PaymentResult res = ps.processPayment("TEST-USER", 10.0);
        assertEquals(PaymentResult.SUCCESS, res);
    }
    
    @Test
    public void testNegative() {
        PaymentService ps = new PaymentService();
        // Call site 16
        ps.processPayment("TEST-NEG", -1.0);
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and ready the environment
wait_for_eclipse 60

# Dismiss dialogs
dismiss_dialogs 3

# Close welcome tab
close_welcome_tab

# Focus Eclipse
focus_eclipse_window
sleep 2

# Record initial timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project 'PaymentPlatform' created with 16 call sites."