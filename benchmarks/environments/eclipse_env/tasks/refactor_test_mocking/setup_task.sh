#!/bin/bash
set -e
echo "=== Setting up Refactor Test Mocking Task ==="

source /workspace/scripts/task_utils.sh

# Define project paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="PaymentSystem"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directory structure
mkdir -p "$PROJECT_DIR/src/main/java/com/example/payment"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/payment"

# 1. Create pom.xml with JUnit 5 and Mockito
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>payment-system</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- JUnit 5 -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
        <!-- Mockito -->
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-core</artifactId>
            <version>5.5.0</version>
            <scope>test</scope>
        </dependency>
        <!-- Mockito JUnit 5 Extension -->
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-junit-jupiter</artifactId>
            <version>5.5.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
EOF

# 2. PaymentProcessor Interface
cat > "$PROJECT_DIR/src/main/java/com/example/payment/PaymentProcessor.java" << 'EOF'
package com.example.payment;

public interface PaymentProcessor {
    boolean processPayment(String orderId, double amount);
}
EOF

# 3. StripePaymentProcessor (The Problematic Dependency)
cat > "$PROJECT_DIR/src/main/java/com/example/payment/StripePaymentProcessor.java" << 'EOF'
package com.example.payment;

public class StripePaymentProcessor implements PaymentProcessor {
    @Override
    public boolean processPayment(String orderId, double amount) {
        // Simulating a network call that fails in test environment
        System.out.println("Connecting to Stripe API...");
        throw new RuntimeException("Network unavailable: Cannot connect to Stripe API");
    }
}
EOF

# 4. OrderService (Class Under Test)
cat > "$PROJECT_DIR/src/main/java/com/example/payment/OrderService.java" << 'EOF'
package com.example.payment;

public class OrderService {
    private PaymentProcessor paymentProcessor;

    public OrderService(PaymentProcessor paymentProcessor) {
        this.paymentProcessor = paymentProcessor;
    }

    public boolean placeOrder(String orderId, double amount) {
        if (amount <= 0) {
            return false;
        }
        return paymentProcessor.processPayment(orderId, amount);
    }
}
EOF

# 5. OrderServiceTest (The Failing Test)
cat > "$PROJECT_DIR/src/test/java/com/example/payment/OrderServiceTest.java" << 'EOF'
package com.example.payment;

import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.Test;

public class OrderServiceTest {

    @Test
    public void testPlaceOrderSuccess() {
        // PROBLEM: This uses the real implementation which fails without network
        PaymentProcessor realProcessor = new StripePaymentProcessor();
        OrderService service = new OrderService(realProcessor);
        
        // This will throw RuntimeException and fail the test
        boolean result = service.placeOrder("ORD-123", 99.99);
        
        assertTrue(result, "Order should be processed successfully");
    }
}
EOF

# Create Eclipse .project file to make it visible/importable
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>PaymentSystem</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

# Create Eclipse .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
            <attribute name="test" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and ensure it's ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="