#!/bin/bash
set -e
echo "=== Setting up refactor_extract_interface task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="payment-platform"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/platform/payment"
mkdir -p "$PROJECT_DIR/src/main/java/com/platform/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/platform/model"

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.platform</groupId>
    <artifactId>payment-platform</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
EOF

# Create Domain Models
cat > "$PROJECT_DIR/src/main/java/com/platform/model/PaymentResult.java" <<EOF
package com.platform.model;
public class PaymentResult {
    private boolean success;
    private String transactionId;
    private String message;
    public PaymentResult(boolean success, String transactionId, String message) {
        this.success = success;
        this.transactionId = transactionId;
        this.message = message;
    }
    public boolean isSuccess() { return success; }
}
EOF

# Create Concrete Service (The refactoring target)
cat > "$PROJECT_DIR/src/main/java/com/platform/payment/StripeService.java" <<EOF
package com.platform.payment;

import com.platform.model.PaymentResult;
import java.math.BigDecimal;
import java.util.UUID;

/**
 * Concrete implementation of Stripe payment processing.
 * This class is currently tightly coupled and needs an interface extracted.
 */
public class StripeService {
    private String apiKey;

    public StripeService() {
        this.apiKey = "sk_live_SimulatedKey";
        connectToStripeAPI();
    }

    // --- BUSINESS METHODS TO EXTRACT ---

    public PaymentResult charge(String customerId, BigDecimal amount, String currency) {
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            return new PaymentResult(false, null, "Invalid amount");
        }
        logTransaction("Charging " + customerId + " " + amount + " " + currency);
        String txId = "tx_" + UUID.randomUUID().toString().substring(0, 8);
        return new PaymentResult(true, txId, "Success");
    }

    public PaymentResult refund(String transactionId, BigDecimal amount) {
        logTransaction("Refunding " + transactionId);
        return new PaymentResult(true, "ref_" + transactionId, "Refunded");
    }

    public boolean verifyCard(String cardToken) {
        return cardToken != null && cardToken.startsWith("tok_");
    }

    // --- INTERNAL METHODS (DO NOT EXTRACT) ---

    private void logTransaction(String message) {
        System.out.println("[Stripe Audit] " + message);
    }
    
    private void connectToStripeAPI() {
        // Internal connection logic
        System.out.println("Connecting to Stripe...");
    }
}
EOF

# Create Dependent Service (Needs to be updated to use interface)
cat > "$PROJECT_DIR/src/main/java/com/platform/service/CheckoutService.java" <<EOF
package com.platform.service;

import com.platform.payment.StripeService;
import com.platform.model.PaymentResult;
import java.math.BigDecimal;

public class CheckoutService {
    // DIRECT DEPENDENCY - BAD FOR TESTING
    private final StripeService paymentService;

    public CheckoutService() {
        this.paymentService = new StripeService();
    }
    
    public CheckoutService(StripeService paymentService) {
        this.paymentService = paymentService;
    }

    public void processOrder(String orderId, BigDecimal total) {
        if (paymentService.verifyCard("tok_visa")) {
            PaymentResult result = paymentService.charge("cus_123", total, "USD");
            if (!result.isSuccess()) {
                throw new RuntimeException("Payment failed");
            }
        }
    }
    
    public void cancelOrder(String orderId) {
        paymentService.refund("tx_old_123", new BigDecimal("10.00"));
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "payment-platform" 120

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="