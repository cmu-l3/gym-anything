#!/bin/bash
set -e
echo "=== Setting up create_logger_live_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the project structure
PROJECT_DIR="/home/ga/IdeaProjects/payment-service"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/payment"
mkdir -p "$PROJECT_DIR/src/test/java"

# 2. Create pom.xml with SLF4J
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>payment-service</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>slf4j-api</artifactId>
      <version>2.0.7</version>
    </dependency>
  </dependencies>
</project>
EOF

# 3. Create the Java class
cat > "$PROJECT_DIR/src/main/java/com/example/payment/PaymentService.java" << 'EOF'
package com.example.payment;

import java.math.BigDecimal;

public class PaymentService {

    // TODO: Add logger here using the 'logger' Live Template

    public void processPayment(String orderId, BigDecimal amount) {
        // Logic would go here
    }
}
EOF

# Ensure permissions
chown -R ga:ga "/home/ga/IdeaProjects"

# 4. Remove any existing Custom templates to ensure clean state
# Find config dir (handling version variations)
CONFIG_DIR=$(find /home/ga/.config/JetBrains -maxdepth 1 -name "IdeaIC*" | head -1)
if [ -n "$CONFIG_DIR" ]; then
    rm -f "$CONFIG_DIR/templates/Custom.xml" 2>/dev/null || true
fi

# 5. Launch IntelliJ with the project
setup_intellij_project "$PROJECT_DIR" "payment-service" 120

# 6. Open the specific file to save the agent a step
echo "Opening PaymentService.java..."
su - ga -c "DISPLAY=:1 /opt/idea/bin/idea.sh '$PROJECT_DIR/src/main/java/com/example/payment/PaymentService.java' > /dev/null 2>&1 &"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="