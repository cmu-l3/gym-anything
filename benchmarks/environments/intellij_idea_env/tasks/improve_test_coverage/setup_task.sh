#!/bin/bash
set -e
echo "=== Setting up improve_test_coverage task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/fintech-risk-engine"
mkdir -p "$PROJECT_DIR/src/main/java/com/fintech/risk"
mkdir -p "$PROJECT_DIR/src/test/java/com/fintech/risk"

# 1. Create POM with JUnit 5 and JaCoCo
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.fintech</groupId>
  <artifactId>risk-engine</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
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
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.0.0</version>
      </plugin>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>0.8.10</version>
        <executions>
          <execution>
            <goals>
              <goal>prepare-agent</goal>
            </goals>
          </execution>
          <execution>
            <id>report</id>
            <phase>test</phase>
            <goals>
              <goal>report</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
EOF

# 2. Create Logic Class (The "Problem" - Complex Logic)
LOGIC_FILE="$PROJECT_DIR/src/main/java/com/fintech/risk/LoanRiskCalculator.java"
cat > "$LOGIC_FILE" << 'EOF'
package com.fintech.risk;

public class LoanRiskCalculator {

    public enum Decision {
        APPROVED,
        REFERRED,
        REJECTED
    }

    /**
     * Determines loan decision based on credit score, annual income, current debt, and requested amount.
     */
    public Decision evaluate(int creditScore, double annualIncome, double currentDebt, double loanAmount) {
        // Basic validation
        if (annualIncome <= 0 || loanAmount <= 0) {
            return Decision.REJECTED;
        }

        // Calculate Debt-to-Income (DTI) including the new loan (assuming 5 year term simple calc)
        double monthlyIncome = annualIncome / 12.0;
        double estimatedNewPayment = loanAmount / 60.0;
        double totalMonthlyDebt = (currentDebt / 12.0) + estimatedNewPayment; 
        double dtiRatio = totalMonthlyDebt / monthlyIncome;

        // Auto-Reject Logic
        if (creditScore < 500) {
            return Decision.REJECTED;
        }
        if (dtiRatio > 0.50) {
            return Decision.REJECTED;
        }

        // Tier 1: Excellent Credit
        if (creditScore >= 750) {
            if (dtiRatio < 0.45) {
                return Decision.APPROVED;
            } else {
                return Decision.REFERRED;
            }
        }

        // Tier 2: Good Credit
        if (creditScore >= 650) {
            if (dtiRatio < 0.36) {
                return Decision.APPROVED;
            } else if (dtiRatio < 0.45 && loanAmount < 20000) {
                return Decision.APPROVED;
            } else {
                return Decision.REFERRED; // Review required
            }
        }

        // Tier 3: Fair Credit (500-649)
        if (dtiRatio < 0.30 && loanAmount < 10000) {
            return Decision.APPROVED;
        }

        return Decision.REFERRED; // Default for risky but not auto-rejected
    }
}
EOF

# 3. Create Incomplete Test Class (Only covers Happy Path)
cat > "$PROJECT_DIR/src/test/java/com/fintech/risk/LoanRiskCalculatorTest.java" << 'EOF'
package com.fintech.risk;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class LoanRiskCalculatorTest {

    private final LoanRiskCalculator calculator = new LoanRiskCalculator();

    @Test
    public void testStandardApproval() {
        // Excellent credit (800), High Income (100k), Low Debt (0), Modest Loan (10k)
        // DTI should be very low -> APPROVED
        LoanRiskCalculator.Decision decision = calculator.evaluate(800, 100000, 0, 10000);
        assertEquals(LoanRiskCalculator.Decision.APPROVED, decision);
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial hash of the logic class (for anti-gaming verification)
md5sum "$LOGIC_FILE" | awk '{print $1}' > /tmp/initial_logic_hash.txt
chmod 644 /tmp/initial_logic_hash.txt

# Pre-compile to speed up agent's first run
echo "Pre-compiling project..."
cd "$PROJECT_DIR" && su - ga -c "mvn compile -q"

# Launch IntelliJ
setup_intellij_project "$PROJECT_DIR" "risk-engine" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="