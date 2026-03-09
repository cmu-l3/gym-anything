#!/bin/bash
set -e
echo "=== Setting up Refactor Constants & Parameters Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="ecommerce-pricing"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/src/main/java/com/example/pricing"

# 1. Create Project Structure
echo "Creating project structure at $PROJECT_DIR..."
mkdir -p "$PACKAGE_DIR"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>ecommerce-pricing</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POM

# 3. Create PricingCalculator.java (The file to refactor)
# Contains magic numbers: 1.0825, 15.00
# Contains magic string: "PLATINUM"
cat > "$PACKAGE_DIR/PricingCalculator.java" << 'JAVA'
package com.example.pricing;

public class PricingCalculator {

    public double calculateFinalPrice(double basePrice, String customerType) {
        // Calculate tax (Magic Number 1)
        double priceWithTax = basePrice * 1.0825;

        // Apply discount if applicable (Magic String)
        if (customerType.equals("PLATINUM")) {
            priceWithTax = priceWithTax * 0.85; // 15% discount
        }

        // Add shipping (Magic Number 2)
        return priceWithTax + 15.00;
    }
}
JAVA

# 4. Create CheckoutService.java (The caller)
cat > "$PACKAGE_DIR/CheckoutService.java" << 'JAVA'
package com.example.pricing;

public class CheckoutService {

    private final PricingCalculator calculator = new PricingCalculator();

    public void processOrder(double amount) {
        // Caller uses the method with 2 arguments currently
        double total = calculator.calculateFinalPrice(amount, "PLATINUM");
        System.out.println("Total due: " + total);
    }
    
    public void processStandardOrder(double amount) {
        double total = calculator.calculateFinalPrice(amount, "STANDARD");
        System.out.println("Total due: " + total);
    }
}
JAVA

# Set permissions
chown -R ga:ga "/home/ga/IdeaProjects"

# 5. Record initial state for verification
date +%s > /tmp/task_start_time.txt
md5sum "$PACKAGE_DIR/PricingCalculator.java" > /tmp/initial_calc_hash.txt
md5sum "$PACKAGE_DIR/CheckoutService.java" > /tmp/initial_service_hash.txt

# 6. Launch IntelliJ and load project
echo "Launching IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "$PROJECT_NAME" 120

# 7. Initial evidence
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="