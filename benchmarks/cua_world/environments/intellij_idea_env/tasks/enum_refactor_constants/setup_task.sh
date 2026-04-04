#!/bin/bash
set -e
echo "=== Setting up enum_refactor_constants task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-processor"
mkdir -p "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Generate the Legacy Maven Project Structure
# ==============================================================================
echo "Generating legacy codebase..."

# Create directory structure
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/constants"
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/processor"
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/fees"
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/validation"
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/report"
mkdir -p "$PROJECT_DIR/src/main/java/com/payments/model" # Empty for now
mkdir -p "$PROJECT_DIR/src/test/java/com/payments/processor"

# 1.1 pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.payments</groupId>
    <artifactId>payment-processor</artifactId>
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
POM

# 1.2 PaymentConstants.java (The Anti-Pattern)
cat > "$PROJECT_DIR/src/main/java/com/payments/constants/PaymentConstants.java" << 'JAVA'
package com.payments.constants;

/**
 * Legacy constants for payment types.
 * TODO: Refactor this to an Enum.
 */
public class PaymentConstants {
    public static final int CREDIT_CARD = 0;
    public static final int DEBIT_CARD = 1;
    public static final int BANK_TRANSFER = 2;
    public static final int DIGITAL_WALLET = 3;
    
    // Prevent instantiation
    private PaymentConstants() {}
}
JAVA

# 1.3 FeeCalculator.java (Logic to move to Enum)
cat > "$PROJECT_DIR/src/main/java/com/payments/fees/FeeCalculator.java" << 'JAVA'
package com.payments.fees;

import com.payments.constants.PaymentConstants;

public class FeeCalculator {
    
    public double calculateFee(double amount, int paymentType) {
        double rate = 0.0;
        
        switch (paymentType) {
            case PaymentConstants.CREDIT_CARD:
                rate = 0.029; // 2.9%
                break;
            case PaymentConstants.DEBIT_CARD:
                rate = 0.015; // 1.5%
                break;
            case PaymentConstants.BANK_TRANSFER:
                rate = 0.005; // 0.5%
                break;
            case PaymentConstants.DIGITAL_WALLET:
                rate = 0.025; // 2.5%
                break;
            default:
                throw new IllegalArgumentException("Unknown payment type: " + paymentType);
        }
        
        return amount * rate;
    }
}
JAVA

# 1.4 PaymentValidator.java
cat > "$PROJECT_DIR/src/main/java/com/payments/validation/PaymentValidator.java" << 'JAVA'
package com.payments.validation;

import com.payments.constants.PaymentConstants;

public class PaymentValidator {
    
    public boolean validate(double amount, int paymentType) {
        if (amount <= 0) return false;
        
        // Simulating specific validation rules
        if (paymentType == PaymentConstants.BANK_TRANSFER && amount > 50000) {
            return false; // Limit for bank transfers
        }
        
        if (paymentType < 0 || paymentType > 3) {
            return false;
        }
        
        return true;
    }
}
JAVA

# 1.5 PaymentReport.java
cat > "$PROJECT_DIR/src/main/java/com/payments/report/PaymentReport.java" << 'JAVA'
package com.payments.report;

import com.payments.constants.PaymentConstants;

public class PaymentReport {
    
    public String getLabel(int paymentType) {
        switch (paymentType) {
            case PaymentConstants.CREDIT_CARD:
                return "Credit Card";
            case PaymentConstants.DEBIT_CARD:
                return "Debit Card";
            case PaymentConstants.BANK_TRANSFER:
                return "Bank Transfer";
            case PaymentConstants.DIGITAL_WALLET:
                return "Digital Wallet";
            default:
                return "Unknown";
        }
    }
}
JAVA

# 1.6 PaymentProcessor.java (Main orchestrator)
cat > "$PROJECT_DIR/src/main/java/com/payments/processor/PaymentProcessor.java" << 'JAVA'
package com.payments.processor;

import com.payments.constants.PaymentConstants;
import com.payments.fees.FeeCalculator;
import com.payments.validation.PaymentValidator;
import com.payments.report.PaymentReport;

public class PaymentProcessor {
    
    private final FeeCalculator feeCalculator = new FeeCalculator();
    private final PaymentValidator validator = new PaymentValidator();
    private final PaymentReport report = new PaymentReport();
    
    public String processPayment(double amount, int paymentType) {
        if (!validator.validate(amount, paymentType)) {
            return "Validation Failed";
        }
        
        double fee = feeCalculator.calculateFee(amount, paymentType);
        double total = amount + fee;
        String typeName = report.getLabel(paymentType);
        
        return String.format("Processed %s payment. Amount: %.2f, Fee: %.3f, Total: %.2f", 
                             typeName, amount, fee, total);
    }
}
JAVA

# 1.7 PaymentProcessorTest.java (Tests to maintain)
cat > "$PROJECT_DIR/src/test/java/com/payments/processor/PaymentProcessorTest.java" << 'JAVA'
package com.payments.processor;

import com.payments.constants.PaymentConstants;
import org.junit.Test;
import static org.junit.Assert.*;

public class PaymentProcessorTest {
    
    private final PaymentProcessor processor = new PaymentProcessor();
    
    @Test
    public void testCreditCardFee() {
        // 100 * 0.029 = 2.9
        String result = processor.processPayment(100.0, PaymentConstants.CREDIT_CARD);
        assertTrue(result.contains("Fee: 2.900"));
        assertTrue(result.contains("Credit Card"));
    }
    
    @Test
    public void testDebitCardFee() {
        // 100 * 0.015 = 1.5
        String result = processor.processPayment(100.0, PaymentConstants.DEBIT_CARD);
        assertTrue(result.contains("Fee: 1.500"));
        assertTrue(result.contains("Debit Card"));
    }
    
    @Test
    public void testBankTransferFee() {
        // 1000 * 0.005 = 5.0
        String result = processor.processPayment(1000.0, PaymentConstants.BANK_TRANSFER);
        assertTrue(result.contains("Fee: 5.000"));
        assertTrue(result.contains("Bank Transfer"));
    }
    
    @Test
    public void testDigitalWalletFee() {
        // 100 * 0.025 = 2.5
        String result = processor.processPayment(100.0, PaymentConstants.DIGITAL_WALLET);
        assertTrue(result.contains("Fee: 2.500"));
        assertTrue(result.contains("Digital Wallet"));
    }
    
    @Test
    public void testInvalidAmount() {
        String result = processor.processPayment(-50.0, PaymentConstants.CREDIT_CARD);
        assertEquals("Validation Failed", result);
    }
    
    @Test
    public void testBankTransferLimit() {
        String result = processor.processPayment(60000.0, PaymentConstants.BANK_TRANSFER);
        assertEquals("Validation Failed", result);
    }
    
    @Test(expected = IllegalArgumentException.class)
    public void testInvalidTypeLogic() {
        // Bypassing validator to hit the calculator switch default for test coverage
        com.payments.fees.FeeCalculator calc = new com.payments.fees.FeeCalculator();
        calc.calculateFee(100, 99);
    }

    @Test
    public void testLabelGeneration() {
        com.payments.report.PaymentReport report = new com.payments.report.PaymentReport();
        assertEquals("Credit Card", report.getLabel(PaymentConstants.CREDIT_CARD));
        assertEquals("Unknown", report.getLabel(99));
    }
}
JAVA

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# ==============================================================================
# 2. Open IntelliJ and Load Project
# ==============================================================================
echo "Launching IntelliJ with payment-processor..."

setup_intellij_project "$PROJECT_DIR" "payment-processor" 180

# Verify it builds initially (optional, but good practice to ensure task is valid)
# cd "$PROJECT_DIR" && su ga -c "mvn compile -q"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="