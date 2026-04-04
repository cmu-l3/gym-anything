#!/bin/bash
set -e
echo "=== Setting up apply_source_cleanup task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/InventoryManager"
SRC_DIR="$PROJECT_DIR/src/com/warehouse"

# 1. clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$SRC_DIR/model"
mkdir -p "$SRC_DIR/service"

# 2. Create Eclipse project metadata
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>InventoryManager</name>
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
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 3. Create Java files with intentional code smells

# Product.java: Missing @Override, Unused imports, Raw types, Unnecessary boxing, String ==
cat > "$SRC_DIR/model/Product.java" << 'EOF'
package com.warehouse.model;

import java.util.List;
import java.util.ArrayList;
import java.util.Date;        // Unused
import java.io.Serializable;  // Unused
import java.util.HashMap;     // Unused

public class Product implements Comparable<Product> {
    private String name;
    private String sku;
    private double price;
    private List tags;  // Raw type

    public Product(String name, String sku) {
        this.name = name;
        this.sku = sku;
        this.tags = new ArrayList(); // Raw type
    }

    // Missing @Override
    public String toString() {
        return "Product[" + name + ", " + sku + "]";
    }

    // Missing @Override
    public int compareTo(Product other) {
        return this.name.compareTo(other.name);
    }

    public boolean hasSameSku(String otherSku) {
        // String equality error
        return this.sku == otherSku;
    }

    public Integer getDiscountedPriceCents() {
        // Unnecessary boxing
        return Integer.valueOf(42);
    }
}
EOF

# Category.java: Missing @Override, String ==
cat > "$SRC_DIR/model/Category.java" << 'EOF'
package com.warehouse.model;

public class Category {
    private String categoryName;
    
    public Category(String name) {
        this.categoryName = name;
    }
    
    public boolean isDefault() {
        // String equality error with literal
        return categoryName == "Default";
    }
    
    // Missing @Override
    public String toString() {
        return categoryName;
    }
}
EOF

# InventoryService.java: Unused imports, Raw types
cat > "$SRC_DIR/service/InventoryService.java" << 'EOF'
package com.warehouse.service;

import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.sql.SQLException; // Unused
import java.util.Set;         // Unused

public class InventoryService {
    private Map inventory = new HashMap(); // Raw type
    
    public void addItem(String sku, int count) {
        inventory.put(sku, count);
    }
    
    public int getCount(String sku) {
        if (inventory.containsKey(sku)) {
            return (Integer) inventory.get(sku);
        }
        return 0;
    }
}
EOF

# Main.java: Entry point (Unused imports)
cat > "$SRC_DIR/Main.java" << 'EOF'
package com.warehouse;

import com.warehouse.model.Product;
import com.warehouse.service.InventoryService;
import java.util.Scanner; // Unused

public class Main {
    public static void main(String[] args) {
        Product p = new Product("Widget", "WID-001");
        System.out.println(p.toString());
        
        InventoryService service = new InventoryService();
        service.addItem("WID-001", 100);
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 4. Wait for Eclipse and load
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss dialogs
dismiss_dialogs 3
close_welcome_tab

# Focus window
focus_eclipse_window
sleep 2

# Force refresh workspace if possible (F5)
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 2

# Open Problems view (Alt+Shift+Q, X is standard shortcut, but let's try menu access via key sequence if needed, or just rely on agent knowing how)
# Better: Just maximize Eclipse so agent can find it.

# Record start time
date +%s > /tmp/task_start_time.txt

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="