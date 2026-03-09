#!/bin/bash
set -e
echo "=== Setting up generate_business_key_equality task ==="

source /workspace/scripts/task_utils.sh

# Configuration
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="InventorySystem"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/src/main/java/com/store/model"

# 1. Clean up any previous run
rm -rf "$PROJECT_DIR"

# 2. Create Project Structure
mkdir -p "$PACKAGE_DIR"
chown -R ga:ga "$PROJECT_DIR"

# 3. Create pom.xml (Standard Maven)
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.store</groupId>
    <artifactId>inventory-system</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POM

# 4. Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << EOFPROJECT
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>$PROJECT_NAME</name>
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
EOFPROJECT

# 5. Create Eclipse .classpath file
cat > "$PROJECT_DIR/.classpath" << EOFCLASSPATH
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
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
EOFCLASSPATH

# 6. Create Product.java (Missing hashCode/equals)
cat > "$PACKAGE_DIR/Product.java" << 'JAVA'
package com.store.model;

import java.math.BigDecimal;
import java.util.Objects;

/**
 * Represents a product in the inventory.
 */
public class Product {
    
    private Long id;            // Database ID (surrogate key)
    private String sku;         // Stock Keeping Unit (BUSINESS KEY)
    private String name;        // Mutable
    private BigDecimal price;   // Mutable
    private int stockQuantity;  // Mutable

    public Product() {}

    public Product(String sku, String name, BigDecimal price) {
        this.sku = sku;
        this.name = name;
        this.price = price;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getSku() { return sku; }
    public void setSku(String sku) { this.sku = sku; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public int getStockQuantity() { return stockQuantity; }
    public void setStockQuantity(int stockQuantity) { this.stockQuantity = stockQuantity; }

    @Override
    public String toString() {
        return "Product[sku=" + sku + ", name=" + name + "]";
    }
}
JAVA

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 7. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_compile_status.txt

# 8. Start Eclipse
# We use setup_eclipse_project to handle waiting, dismissal of dialogs, etc.
# But since we created the project manually in the workspace, we assume Eclipse picks it up on launch.
# We will explicitly open the file.

echo "Starting Eclipse..."
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected, might need manual start or is starting up."

# Force open the file to ensure agent sees it
echo "Opening Product.java..."
su - ga -c "DISPLAY=:1 eclipse \"$PACKAGE_DIR/Product.java\" &"

# Wait for window and maximize
wait_for_eclipse 120
focus_eclipse_window
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="