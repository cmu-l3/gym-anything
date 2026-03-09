#!/bin/bash
echo "=== Setting up refactor_to_parameterized_tests task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/security-utils"

# clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/security"
mkdir -p "$PROJECT_DIR/src/test/java/com/security"

# 1. Create POM with JUnit 5
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.security</groupId>
  <artifactId>security-utils</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
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
    </plugins>
  </build>
</project>
EOF

# 2. Create Implementation
cat > "$PROJECT_DIR/src/main/java/com/security/PasswordValidator.java" << 'EOF'
package com.security;

public class PasswordValidator {
    public boolean validate(String password) {
        if (password == null) return false;
        if (password.length() < 8) return false;
        if (password.length() > 30) return false;
        if (!password.matches(".*[A-Z].*")) return false;
        if (!password.matches(".*\\d.*")) return false;
        if (password.contains(" ")) return false;
        return true;
    }
}
EOF

# 3. Create Repetitive Tests (The target for refactoring)
cat > "$PROJECT_DIR/src/test/java/com/security/PasswordValidatorTest.java" << 'EOF'
package com.security;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class PasswordValidatorTest {

    private final PasswordValidator validator = new PasswordValidator();

    @Test
    public void testValidPassword() {
        assertTrue(validator.validate("SecurePass123"), "Should be valid");
    }

    @Test
    public void testTooShort() {
        assertFalse(validator.validate("Short1"), "Too short");
    }

    @Test
    public void testNoDigit() {
        assertFalse(validator.validate("NoDigitHere"), "Missing digit");
    }

    @Test
    public void testNoUppercase() {
        assertFalse(validator.validate("nouppercase123"), "Missing uppercase");
    }

    @Test
    public void testHasWhitespace() {
        assertFalse(validator.validate("Space 123"), "Has whitespace");
    }

    @Test
    public void testEmpty() {
        assertFalse(validator.validate(""), "Empty string");
    }

    @Test
    public void testNull() {
        assertFalse(validator.validate(null), "Null input");
    }

    @Test
    public void testVeryLongPassword() {
        String longPass = "ThisPasswordIsWayTooLongAndShouldFailValidation123";
        assertFalse(validator.validate(longPass), "Too long");
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Pre-warm Maven (download dependencies and ensure tests pass initially)
echo "Pre-warming Maven..."
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test -q"

# Record initial test file hash (to detect if agent actually changes it)
md5sum "$PROJECT_DIR/src/test/java/com/security/PasswordValidatorTest.java" > /tmp/initial_test_hash.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "security-utils" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="