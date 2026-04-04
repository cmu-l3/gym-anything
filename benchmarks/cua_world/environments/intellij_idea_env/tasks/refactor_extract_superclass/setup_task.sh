#!/bin/bash
set -e
echo "=== Setting up refactor_extract_superclass task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="banking-system"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/src/main/java/com/banking"
TEST_DIR="$PROJECT_DIR/src/test/java/com/banking"

# 1. Create Project Structure
echo "Creating Maven project structure..."
mkdir -p "$PACKAGE_DIR"
mkdir -p "$TEST_DIR"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.banking</groupId>
  <artifactId>banking-system</artifactId>
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

# 3. Create CheckingAccount.java (Duplicate logic)
cat > "$PACKAGE_DIR/CheckingAccount.java" << 'JAVA'
package com.banking;

public class CheckingAccount {
    private String accountNumber;
    private double balance;
    private String owner;
    private double overdraftLimit;

    public CheckingAccount(String accountNumber, String owner, double overdraftLimit) {
        this.accountNumber = accountNumber;
        this.owner = owner;
        this.balance = 0.0;
        this.overdraftLimit = overdraftLimit;
    }

    public void deposit(double amount) {
        if (amount > 0) {
            this.balance += amount;
        }
    }

    public void withdraw(double amount) {
        if (amount > 0 && (balance + overdraftLimit) >= amount) {
            this.balance -= amount;
        }
    }

    public double getBalance() {
        return balance;
    }

    public String getOwner() {
        return owner;
    }

    // Specific to Checking
    public void processCheck(String checkNumber, double amount) {
        withdraw(amount);
        System.out.println("Processed check " + checkNumber);
    }
}
JAVA

# 4. Create SavingsAccount.java (Duplicate logic)
cat > "$PACKAGE_DIR/SavingsAccount.java" << 'JAVA'
package com.banking;

public class SavingsAccount {
    private String accountNumber;
    private double balance;
    private String owner;
    private double interestRate;

    public SavingsAccount(String accountNumber, String owner, double interestRate) {
        this.accountNumber = accountNumber;
        this.owner = owner;
        this.balance = 0.0;
        this.interestRate = interestRate;
    }

    public void deposit(double amount) {
        if (amount > 0) {
            this.balance += amount;
        }
    }

    public void withdraw(double amount) {
        if (amount > 0 && balance >= amount) {
            this.balance -= amount;
        }
    }

    public double getBalance() {
        return balance;
    }

    public String getOwner() {
        return owner;
    }

    // Specific to Savings
    public void addInterest() {
        double interest = balance * interestRate;
        deposit(interest);
    }
}
JAVA

# 5. Create AccountTest.java (Verification)
cat > "$TEST_DIR/AccountTest.java" << 'JAVA'
package com.banking;

import org.junit.Test;
import static org.junit.Assert.*;

public class AccountTest {
    @Test
    public void testCheckingDepositWithdraw() {
        CheckingAccount ca = new CheckingAccount("CK123", "Alice", 100.0);
        ca.deposit(500.0);
        assertEquals(500.0, ca.getBalance(), 0.001);
        ca.withdraw(200.0);
        assertEquals(300.0, ca.getBalance(), 0.001);
    }

    @Test
    public void testSavingsDepositWithdraw() {
        SavingsAccount sa = new SavingsAccount("SV456", "Bob", 0.05);
        sa.deposit(1000.0);
        assertEquals(1000.0, sa.getBalance(), 0.001);
        sa.withdraw(200.0);
        assertEquals(800.0, sa.getBalance(), 0.001);
    }
    
    @Test
    public void testPolymorphismLikelihood() {
        // This test just ensures basic functionality remains. 
        // Real polymorphism check is done by parsing source code in verifier.
        assertTrue(true);
    }
}
JAVA

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open IntelliJ
echo "Launching IntelliJ with project..."
setup_intellij_project "$PROJECT_DIR" "banking-system" 120

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="