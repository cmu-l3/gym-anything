#!/bin/bash
set -e
echo "=== Setting up migrate_junit4_to_junit5 task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-service"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/banking"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/banking"

# 1. Generate POM.xml (JUnit 4 state)
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>banking-service</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- Legacy JUnit 4 Dependency -->
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.12</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# 2. Generate Source Code

# Account.java
cat > "$PROJECT_DIR/src/main/java/com/example/banking/Account.java" << 'EOF'
package com.example.banking;

import java.math.BigDecimal;

public class Account {
    private String id;
    private BigDecimal balance;
    private boolean active;

    public Account(String id, BigDecimal initialBalance) {
        this.id = id;
        this.balance = initialBalance;
        this.active = true;
    }

    public void deposit(BigDecimal amount) {
        if (!active) throw new IllegalStateException("Account is inactive");
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Deposit amount must be positive");
        }
        balance = balance.add(amount);
    }

    public void withdraw(BigDecimal amount) {
        if (!active) throw new IllegalStateException("Account is inactive");
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Withdrawal amount must be positive");
        }
        if (balance.compareTo(amount) < 0) {
            throw new InsufficientFundsException("Insufficient funds");
        }
        balance = balance.subtract(amount);
    }

    public BigDecimal getBalance() {
        return balance;
    }

    public void close() {
        this.active = false;
    }
    
    public boolean isActive() {
        return active;
    }
}
EOF

# InsufficientFundsException.java
cat > "$PROJECT_DIR/src/main/java/com/example/banking/InsufficientFundsException.java" << 'EOF'
package com.example.banking;

public class InsufficientFundsException extends RuntimeException {
    public InsufficientFundsException(String message) {
        super(message);
    }
}
EOF

# TransactionService.java
cat > "$PROJECT_DIR/src/main/java/com/example/banking/TransactionService.java" << 'EOF'
package com.example.banking;

import java.math.BigDecimal;

public class TransactionService {
    public void transfer(Account from, Account to, BigDecimal amount) {
        if (from == null || to == null) {
            throw new IllegalArgumentException("Accounts cannot be null");
        }
        from.withdraw(amount);
        to.deposit(amount);
    }
}
EOF

# 3. Generate JUnit 4 Test Code (The Legacy Code to Migrate)

# AccountTest.java - Uses standard Assert, @Test, @Before
cat > "$PROJECT_DIR/src/test/java/com/example/banking/AccountTest.java" << 'EOF'
package com.example.banking;

import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import java.math.BigDecimal;

public class AccountTest {

    private Account account;

    @Before
    public void setUp() {
        account = new Account("123", new BigDecimal("100.00"));
    }

    @After
    public void tearDown() {
        account = null;
    }

    @Test
    public void testDeposit() {
        account.deposit(new BigDecimal("50.00"));
        // JUnit 4: message, expected, actual
        Assert.assertEquals("Balance should be updated correctly", new BigDecimal("150.00"), account.getBalance());
    }

    @Test
    public void testWithdraw() {
        account.withdraw(new BigDecimal("30.00"));
        Assert.assertEquals(new BigDecimal("70.00"), account.getBalance());
    }
    
    @Test
    public void testIsActive() {
        Assert.assertTrue("Account should be initially active", account.isActive());
        account.close();
        Assert.assertFalse("Account should be inactive after closing", account.isActive());
    }
    
    @Test(expected = InsufficientFundsException.class)
    public void testOverdraft() {
        account.withdraw(new BigDecimal("200.00"));
    }
    
    @Test(expected = IllegalArgumentException.class)
    public void testNegativeDeposit() {
        account.deposit(new BigDecimal("-10.00"));
    }
}
EOF

# TransactionServiceTest.java - Uses @BeforeClass, @Test(expected)
cat > "$PROJECT_DIR/src/test/java/com/example/banking/TransactionServiceTest.java" << 'EOF'
package com.example.banking;

import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import java.math.BigDecimal;

public class TransactionServiceTest {

    private TransactionService service;
    private Account acctA;
    private Account acctB;

    @Before
    public void init() {
        service = new TransactionService();
        acctA = new Account("A", new BigDecimal("1000"));
        acctB = new Account("B", new BigDecimal("500"));
    }

    @Test
    public void testTransferSuccess() {
        service.transfer(acctA, acctB, new BigDecimal("100"));
        
        Assert.assertEquals("Sender balance wrong", new BigDecimal("900"), acctA.getBalance());
        Assert.assertEquals("Receiver balance wrong", new BigDecimal("600"), acctB.getBalance());
    }

    @Test(expected = InsufficientFundsException.class)
    public void testTransferInsufficientFunds() {
        service.transfer(acctA, acctB, new BigDecimal("2000"));
    }
    
    @Test(expected = IllegalArgumentException.class)
    public void testTransferNullAccount() {
        service.transfer(null, acctB, new BigDecimal("50"));
    }
    
    @Test
    public void testMixedAssertions() {
        Assert.assertNotNull(service);
        Assert.assertNotEquals(acctA, acctB);
    }
}
EOF

# Create extra tests to reach 15 total (simple ones)
cat > "$PROJECT_DIR/src/test/java/com/example/banking/ExtraTest.java" << 'EOF'
package com.example.banking;
import org.junit.Test;
import org.junit.Assert;
public class ExtraTest {
    @Test public void t1() { Assert.assertEquals(1, 1); }
    @Test public void t2() { Assert.assertTrue(true); }
    @Test public void t3() { Assert.assertFalse(false); }
    @Test public void t4() { Assert.assertNotNull("object"); }
    @Test public void t5() { Assert.assertNull(null); }
    @Test public void t6() { Assert.assertEquals("msg", 2, 2); }
    @Test public void t7() { Assert.assertNotEquals(1, 2); }
    @Test public void t8() { Assert.assertEquals(5, 5); }
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Pre-warm maven (optional but good for speed)
# We won't do full install to avoid downloading junit 5 yet, letting the agent do it.

# Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "banking-service" 180

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="