#!/bin/bash
set -e
echo "=== Setting up Encapsulate Field Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

PROJECT_NAME="InventorySystem"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR"

# 1. Create Project Directory Structure
mkdir -p "$PROJECT_DIR/src/com/inventory/core"
mkdir -p "$PROJECT_DIR/src/com/inventory/service"
mkdir -p "$PROJECT_DIR/src/com/inventory/test"
mkdir -p "$PROJECT_DIR/bin"
mkdir -p "$PROJECT_DIR/.settings"

# 2. Generate Product.java (The Target - Legacy Code)
cat > "$PROJECT_DIR/src/com/inventory/core/Product.java" << 'EOF'
package com.inventory.core;

/**
 * Represents a product in the inventory.
 * Currently uses public fields (Legacy design).
 */
public class Product {
    
    public String sku;
    public String name;
    public double price;
    public int stockQuantity;
    
    public Product(String sku, String name, double price, int stockQuantity) {
        this.sku = sku;
        this.name = name;
        this.price = price;
        this.stockQuantity = stockQuantity;
    }
    
    @Override
    public String toString() {
        return String.format("%s: %s ($%.2f) - Qty: %d", sku, name, price, stockQuantity);
    }
}
EOF

# 3. Generate InventoryManager.java (The Client Code - Direct Access)
cat > "$PROJECT_DIR/src/com/inventory/service/InventoryManager.java" << 'EOF'
package com.inventory.service;

import java.util.ArrayList;
import java.util.List;
import com.inventory.core.Product;

public class InventoryManager {
    
    private List<Product> products = new ArrayList<>();
    
    public void addProduct(Product p) {
        products.add(p);
    }
    
    public void applyDiscount(double percentage) {
        for (Product p : products) {
            // Read and Write access
            double originalPrice = p.price;
            p.price = originalPrice * (1.0 - percentage);
            System.out.println("Updated price for " + p.name + " to " + p.price);
        }
    }
    
    public void restock(String sku, int amount) {
        for (Product p : products) {
            // Read access
            if (p.sku.equals(sku)) {
                // Write access
                p.stockQuantity += amount;
                System.out.println("Restocked " + p.name + ". New Qty: " + p.stockQuantity);
            }
        }
    }
    
    public double getTotalValue() {
        double total = 0;
        for (Product p : products) {
            total += (p.price * p.stockQuantity);
        }
        return total;
    }
}
EOF

# 4. Generate ProductTest.java (Verification Code)
cat > "$PROJECT_DIR/src/com/inventory/test/ProductTest.java" << 'EOF'
package com.inventory.test;

import com.inventory.core.Product;
import com.inventory.service.InventoryManager;

public class ProductTest {
    public static void main(String[] args) {
        Product p1 = new Product("SKU-001", "Laptop", 1200.00, 10);
        Product p2 = new Product("SKU-002", "Mouse", 25.50, 100);
        
        // Direct field access usage
        System.out.println("Checking " + p1.name);
        
        InventoryManager mgr = new InventoryManager();
        mgr.addProduct(p1);
        mgr.addProduct(p2);
        
        System.out.println("Total Value: " + mgr.getTotalValue());
        
        mgr.applyDiscount(0.10); // 10% off
        mgr.restock("SKU-001", 5);
        
        System.out.println("Final Value: " + mgr.getTotalValue());
    }
}
EOF

# 5. Create Eclipse Project Metadata
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>InventorySystem</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 6. Configure Project Settings (Java 17)
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'EOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 7. Initial Compilation (to ensure starting state is valid)
echo "Compiling initial project..."
su - ga -c "javac -d $PROJECT_DIR/bin -sourcepath $PROJECT_DIR/src $PROJECT_DIR/src/com/inventory/test/ProductTest.java"

# 8. Start Eclipse and Open the Project
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Import project automatically if possible, or assume workspace is set to parent dir
# Since setup_eclipse.sh sets workspace to /home/ga/eclipse-workspace, and we put the folder there,
# we just need to restart Eclipse or refresh. But Eclipse might not see it if added while running.
# Safest: Use File > Open File... no, that's for files.
# We will just rely on the user finding it or Eclipse picking it up on refresh.
# Actually, the best UX is to open the file `Product.java` in the editor.

focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Open Product.java using xdotool to simulate Ctrl+Shift+R (Open Resource)
echo "Opening Product.java..."
sleep 2
DISPLAY=:1 xdotool key ctrl+shift+r
sleep 1.5
DISPLAY=:1 xdotool type "Product"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="