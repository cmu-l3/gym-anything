#!/bin/bash
set -e
echo "=== Setting up implement_mockito_tests task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-system"
mkdir -p "$PROJECT_DIR/src/main/java/com/payment"
mkdir -p "$PROJECT_DIR/src/test/java/com/payment"

# ==============================================================================
# Generate Project Files
# ==============================================================================

# 1. POM.xml (Missing dependencies)
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.payment</groupId>
    <artifactId>payment-system</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- Agent needs to add JUnit 5 and Mockito here -->
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.0.0</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# 2. Domain Objects
cat > "$PROJECT_DIR/src/main/java/com/payment/PaymentRequest.java" << 'EOF'
package com.payment;

public class PaymentRequest {
    private String token;
    private double amount;

    public PaymentRequest(String token, double amount) {
        this.token = token;
        this.amount = amount;
    }

    public String getToken() { return token; }
    public double getAmount() { return amount; }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/payment/TransactionStatus.java" << 'EOF'
package com.payment;

public enum TransactionStatus {
    SUCCESS, DECLINED, ERROR
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/payment/Transaction.java" << 'EOF'
package com.payment;

public class Transaction {
    private final String token;
    private final double amount;
    private TransactionStatus status;

    public Transaction(PaymentRequest request) {
        this.token = request.getToken();
        this.amount = request.getAmount();
    }

    public void setStatus(TransactionStatus status) {
        this.status = status;
    }

    public TransactionStatus getStatus() { return status; }
}
EOF

# 3. Interfaces (Dependencies)
cat > "$PROJECT_DIR/src/main/java/com/payment/CreditCardProcessor.java" << 'EOF'
package com.payment;

public interface CreditCardProcessor {
    /**
     * Charges the credit card.
     * @return true if successful, false if declined
     * @throws RuntimeException if network fails
     */
    boolean charge(String token, double amount);
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/payment/TransactionRepository.java" << 'EOF'
package com.payment;

public interface TransactionRepository {
    void save(Transaction transaction);
}
EOF

# 4. Service (The Class Under Test)
cat > "$PROJECT_DIR/src/main/java/com/payment/PaymentService.java" << 'EOF'
package com.payment;

public class PaymentService {
    private final CreditCardProcessor processor;
    private final TransactionRepository repository;

    public PaymentService(CreditCardProcessor processor, TransactionRepository repository) {
        this.processor = processor;
        this.repository = repository;
    }

    public boolean processPayment(PaymentRequest request) {
        Transaction txn = new Transaction(request);
        try {
            boolean success = processor.charge(request.getToken(), request.getAmount());
            if (success) {
                txn.setStatus(TransactionStatus.SUCCESS);
            } else {
                txn.setStatus(TransactionStatus.DECLINED);
            }
            repository.save(txn);
            return success;
        } catch (Exception e) {
            txn.setStatus(TransactionStatus.ERROR);
            repository.save(txn);
            return false;
        }
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# IntelliJ Setup
# ==============================================================================

# Open project
setup_intellij_project "$PROJECT_DIR" "payment-system" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="