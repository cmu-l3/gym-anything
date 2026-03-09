#!/bin/bash
set -e
echo "=== Setting up reverse_engineer_legacy_jar task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-gateway"
mkdir -p "$PROJECT_DIR/lib"
mkdir -p "$PROJECT_DIR/src/test/java/com/payment/gateway"

# ------------------------------------------------------------------
# 1. Create the secret LegacyValidator JAR (without source)
# ------------------------------------------------------------------
echo "Generating legacy library..."
BUILD_DIR=$(mktemp -d)
mkdir -p "$BUILD_DIR/com/legacy/security"

# Create the source file with the "secret" logic
cat > "$BUILD_DIR/com/legacy/security/LegacyValidator.java" << 'EOF'
package com.legacy.security;

/**
 * LEGACY COMPONENT - DO NOT MODIFY
 * Source code lost. Decompiled version only.
 */
public class LegacyValidator {
    // The secret logic the agent must find via decompilation
    private static final String REQUIRED_PREFIX = "SEC-V2-";
    private static final int REQUIRED_LENGTH = 16;

    public static boolean validate(String transactionId) {
        if (transactionId == null) {
            return false;
        }
        // Check 1: Length must be exactly 16
        if (transactionId.length() != REQUIRED_LENGTH) {
            return false;
        }
        // Check 2: Must start with specific prefix
        if (!transactionId.startsWith(REQUIRED_PREFIX)) {
            return false;
        }
        
        // Check 3: Last character must be an even digit
        char lastChar = transactionId.charAt(transactionId.length() - 1);
        if (!Character.isDigit(lastChar)) {
            return false;
        }
        int lastDigit = lastChar - '0';
        return lastDigit % 2 == 0;
    }
}
EOF

# Compile it
javac "$BUILD_DIR/com/legacy/security/LegacyValidator.java"

# Package into JAR
cd "$BUILD_DIR"
jar cf legacy-auth-1.0.jar com/legacy/security/LegacyValidator.class

# Move JAR to project and cleanup source
mv legacy-auth-1.0.jar "$PROJECT_DIR/lib/"
rm -rf "$BUILD_DIR"

# ------------------------------------------------------------------
# 2. Create the Project POM
# ------------------------------------------------------------------
echo "Creating pom.xml..."
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.payment</groupId>
    <artifactId>payment-gateway</artifactId>
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
        <!-- System dependency for the legacy jar -->
        <dependency>
            <groupId>com.legacy</groupId>
            <artifactId>legacy-auth</artifactId>
            <version>1.0</version>
            <scope>system</scope>
            <systemPath>${project.basedir}/lib/legacy-auth-1.0.jar</systemPath>
        </dependency>
    </dependencies>
</project>
EOF

# ------------------------------------------------------------------
# 3. Create the failing test
# ------------------------------------------------------------------
echo "Creating failing test..."
cat > "$PROJECT_DIR/src/test/java/com/payment/gateway/TransactionTest.java" << 'EOF'
package com.payment.gateway;

import com.legacy.security.LegacyValidator;
import org.junit.Test;
import static org.junit.Assert.assertTrue;

public class TransactionTest {

    @Test
    public void testValidTransaction() {
        // TODO: Update this ID to pass the legacy validation
        // The previous developer left a note: "Check the jar, source is lost"
        String transactionId = "12345"; 
        
        System.out.println("Testing Transaction ID: " + transactionId);
        boolean isValid = LegacyValidator.validate(transactionId);
        
        assertTrue("Transaction ID rejected by LegacyValidator", isValid);
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial state hashes
md5sum "$PROJECT_DIR/src/test/java/com/payment/gateway/TransactionTest.java" > /tmp/initial_test_hash.txt
date +%s > /tmp/task_start_time.txt

# ------------------------------------------------------------------
# 4. Launch IntelliJ
# ------------------------------------------------------------------
# Open the project in IntelliJ and wait for it to fully load
setup_intellij_project "$PROJECT_DIR" "payment-gateway" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="