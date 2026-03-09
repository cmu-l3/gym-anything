#!/bin/bash
set -e
echo "=== Setting up generate_coverage_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -rf /home/ga/coverage-report 2>/dev/null || true
rm -rf /home/ga/eclipse-workspace/FinTechCalc 2>/dev/null || true

# Define Project Paths
PROJECT_ROOT="/home/ga/eclipse-workspace/FinTechCalc"
SRC_MAIN="$PROJECT_ROOT/src/main/java/com/fintech/calc"
SRC_TEST="$PROJECT_ROOT/src/test/java/com/fintech/calc"

# Create Directories
mkdir -p "$SRC_MAIN"
mkdir -p "$SRC_TEST"
mkdir -p "$PROJECT_ROOT/.settings"

# 1. Create pom.xml
cat > "$PROJECT_ROOT/pom.xml" << 'EOF_POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.fintech</groupId>
  <artifactId>FinTechCalc</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
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
</project>
EOF_POM

# 2. Create LoanCalculator.java
cat > "$SRC_MAIN/LoanCalculator.java" << 'EOF_SRC'
package com.fintech.calc;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;

public class LoanCalculator {
    
    private static final int MONTHS_PER_YEAR = 12;
    private static final BigDecimal HUNDRED = new BigDecimal("100");
    
    public BigDecimal calculateMonthlyPayment(BigDecimal principal, BigDecimal annualRatePercent, int termYears) {
        validateInputs(principal, annualRatePercent, termYears);
        
        if (annualRatePercent.compareTo(BigDecimal.ZERO) == 0) {
            return principal.divide(BigDecimal.valueOf(termYears * MONTHS_PER_YEAR), 2, RoundingMode.HALF_UP);
        }
        
        BigDecimal monthlyRate = annualRatePercent
            .divide(HUNDRED, 10, RoundingMode.HALF_UP)
            .divide(BigDecimal.valueOf(MONTHS_PER_YEAR), 10, RoundingMode.HALF_UP);
            
        int totalPayments = termYears * MONTHS_PER_YEAR;
        
        BigDecimal onePlusRate = BigDecimal.ONE.add(monthlyRate);
        BigDecimal compoundFactor = onePlusRate.pow(totalPayments);
        
        BigDecimal numerator = principal.multiply(monthlyRate).multiply(compoundFactor);
        BigDecimal denominator = compoundFactor.subtract(BigDecimal.ONE);
        
        return numerator.divide(denominator, 2, RoundingMode.HALF_UP);
    }
    
    private void validateInputs(BigDecimal principal, BigDecimal rate, int years) {
        if (principal == null || principal.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Principal must be positive");
        }
        if (rate == null || rate.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Rate cannot be negative");
        }
        if (years <= 0 || years > 100) {
            throw new IllegalArgumentException("Term must be between 1 and 100 years");
        }
    }
}
EOF_SRC

# 3. Create LoanCalculatorTest.java
cat > "$SRC_TEST/LoanCalculatorTest.java" << 'EOF_TEST'
package com.fintech.calc;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
import java.math.BigDecimal;

class LoanCalculatorTest {

    private LoanCalculator calc = new LoanCalculator();

    @Test
    void testStandard30YearFixed() {
        // $300,000 at 5.0% for 30 years -> $1610.46
        BigDecimal payment = calc.calculateMonthlyPayment(
            new BigDecimal("300000"), 
            new BigDecimal("5.0"), 
            30
        );
        assertEquals(new BigDecimal("1610.46"), payment);
    }

    @Test
    void testZeroInterest() {
        // $12,000 at 0% for 1 year -> $1000/mo
        BigDecimal payment = calc.calculateMonthlyPayment(
            new BigDecimal("12000"), 
            BigDecimal.ZERO, 
            1
        );
        assertEquals(new BigDecimal("1000.00"), payment);
    }
}
EOF_TEST

# 4. Create Eclipse Project Config (.project)
cat > "$PROJECT_ROOT/.project" << 'EOF_PROJ'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>FinTechCalc</name>
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
EOF_PROJ

# 5. Create Eclipse Classpath (.classpath)
cat > "$PROJECT_ROOT/.classpath" << 'EOF_CP'
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
EOF_CP

# 6. Configure Eclipse JDT Settings
cat > "$PROJECT_ROOT/.settings/org.eclipse.jdt.core.prefs" << 'EOF_PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
EOF_PREFS

# Fix permissions
chown -R ga:ga "$PROJECT_ROOT"

# Start Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
dismiss_dialogs 3
close_welcome_tab
focus_eclipse_window
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="