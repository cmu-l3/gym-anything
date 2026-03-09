#!/bin/bash
set -e

echo "=== Setting up generate_data_class_methods task ==="
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Create Project Structure
PROJECT_ROOT="/home/ga/IdeaProjects/data-models"
mkdir -p "$PROJECT_ROOT/src/main/java/com/example/models"

# 3. Create pom.xml
cat > "$PROJECT_ROOT/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>data-models</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
POMEOF

# 4. Create Java classes with fields only (no methods)

# Person.java
cat > "$PROJECT_ROOT/src/main/java/com/example/models/Person.java" << 'JAVAEOF'
package com.example.models;

public class Person {
    private String firstName;
    private String lastName;
    private int age;
    private String email;
}
JAVAEOF

# Address.java
cat > "$PROJECT_ROOT/src/main/java/com/example/models/Address.java" << 'JAVAEOF'
package com.example.models;

public class Address {
    private String street;
    private String city;
    private String state;
    private String zipCode;
    private String country;
}
JAVAEOF

# Order.java
cat > "$PROJECT_ROOT/src/main/java/com/example/models/Order.java" << 'JAVAEOF'
package com.example.models;

import java.time.LocalDate;
import java.util.List;

public class Order {
    private long orderId;
    private String customerName;
    private List<String> items;
    private double totalAmount;
    private LocalDate orderDate;
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_ROOT"

# 5. Pre-resolve dependencies to avoid download delays during task
echo "Resolving dependencies..."
su - ga -c "cd $PROJECT_ROOT && mvn dependency:resolve -q"

# 6. Launch IntelliJ with the project
setup_intellij_project "$PROJECT_ROOT" "data-models" 120

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="