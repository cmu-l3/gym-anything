#!/bin/bash
set -e

echo "=== Setting up resolve_merge_conflicts task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="commons-inventory"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Initialize Git Repo
cd "$PROJECT_DIR"
git init
git config user.email "ga@example.com"
git config user.name "GA User"

# 2. Create Directory Structure
mkdir -p src/main/java/com/inventory/model
mkdir -p src/main/java/com/inventory/service
mkdir -p src/main/java/com/inventory/util

# 3. Create BASE content (Initial Commit)
cat > pom.xml << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.inventory</groupId>
    <artifactId>commons-inventory</artifactId>
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
        <!-- Dependencies start here -->
    </dependencies>
</project>
EOF

cat > src/main/java/com/inventory/model/Product.java << 'EOF'
package com.inventory.model;

public class Product {
    private String id;
    private String name;
    private double price;

    public Product(String id, String name, double price) {
        this.id = id;
        this.name = name;
        this.price = price;
    }

    public String getId() { return id; }
    public String getName() { return name; }
    public double getPrice() { return price; }

    @Override
    public String toString() {
        return "Product{id='" + id + "', name='" + name + "', price=" + price + "}";
    }
}
EOF

cat > src/main/java/com/inventory/service/InventoryManager.java << 'EOF'
package com.inventory.service;

import com.inventory.model.Product;
import java.util.List;
import java.util.ArrayList;

public class InventoryManager {
    private List<Product> products = new ArrayList<>();

    public void addProduct(Product p) {
        products.add(p);
    }

    // BASE IMPLEMENTATION
    public double calculateTotalValue() {
        double total = 0;
        for (Product p : products) {
            total += p.getPrice();
        }
        return total;
    }
}
EOF

cat > src/main/java/com/inventory/util/InventoryUtils.java << 'EOF'
package com.inventory.util;

public class InventoryUtils {
    // Utility methods for inventory management
    
    public static boolean isValidId(String id) {
        return id != null && !id.isEmpty();
    }
}
EOF

git add .
git commit -m "Initial commit"

# 4. Create MAIN branch changes (The "Their" changes)
# - Add category field to Product
# - Refactor InventoryManager to use Streams
# - Add formatCurrency to Utils
# - Add commons-lang3 to POM

git checkout -b main_temp
# Modify Product
sed -i '/private double price;/a \    private String category;' src/main/java/com/inventory/model/Product.java
sed -i '/this.price = price;/a \        this.category = "General";' src/main/java/com/inventory/model/Product.java
sed -i '/public double getPrice() { return price; }/a \    public String getCategory() { return category; }\n    public void setCategory(String category) { this.category = category; }' src/main/java/com/inventory/model/Product.java
# Replace toString to cause conflict
sed -i '/return "Product{id=/c\        return "Product{id=" + id + ", name=" + name + ", price=" + price + ", category=" + category + "}";' src/main/java/com/inventory/model/Product.java

# Modify InventoryManager (Stream refactor)
cat > src/main/java/com/inventory/service/InventoryManager.java << 'EOF'
package com.inventory.service;

import com.inventory.model.Product;
import java.util.List;
import java.util.ArrayList;

public class InventoryManager {
    private List<Product> products = new ArrayList<>();

    public void addProduct(Product p) {
        products.add(p);
    }

    // Refactored to use Streams
    public double calculateTotalValue() {
        return products.stream()
                .mapToDouble(Product::getPrice)
                .sum();
    }
}
EOF

# Modify InventoryUtils
sed -i '/public static boolean isValidId/i \    public static String formatCurrency(double amount) {\n        return String.format("$%.2f", amount);\n    }\n' src/main/java/com/inventory/util/InventoryUtils.java

# Modify POM
sed -i '/<!-- Dependencies start here -->/a \        <dependency>\n            <groupId>org.apache.commons</groupId>\n            <artifactId>commons-lang3</artifactId>\n            <version>3.14.0</version>\n        </dependency>' pom.xml

git commit -am "Refactor: Add categories, streams, and currency formatting"
git branch -M main
git branch -D main_temp 2>/dev/null || true


# 5. Create FEATURE branch changes (The "Our" changes)
# - Add discountPercent field to Product
# - Add calculateDiscountedTotal to InventoryManager
# - Add calculateBulkDiscount to Utils
# - Add commons-math3 to POM

git checkout -b feature/discount-system HEAD~1 # Go back to initial commit

# Modify Product
sed -i '/private double price;/a \    private double discountPercent;' src/main/java/com/inventory/model/Product.java
sed -i '/this.price = price;/a \        this.discountPercent = 0.0;' src/main/java/com/inventory/model/Product.java
sed -i '/public double getPrice() { return price; }/a \    public double getDiscountPercent() { return discountPercent; }\n    public void setDiscountPercent(double discountPercent) { this.discountPercent = discountPercent; }' src/main/java/com/inventory/model/Product.java
# Replace toString (CONFLICT)
sed -i '/return "Product{id=/c\        return "Product{id=" + id + ", name=" + name + ", price=" + price + ", discount=" + discountPercent + "%}";' src/main/java/com/inventory/model/Product.java

# Modify InventoryManager
# We want to replace the same block to cause conflict, OR insert at same line.
# The base had the loop implementation. We will keep the loop but add a new method right after it.
# To force conflict with Main's replacement, we'll modify the loop slightly or just place the new method exactly where Main touched.
cat > src/main/java/com/inventory/service/InventoryManager.java << 'EOF'
package com.inventory.service;

import com.inventory.model.Product;
import java.util.List;
import java.util.ArrayList;

public class InventoryManager {
    private List<Product> products = new ArrayList<>();

    public void addProduct(Product p) {
        products.add(p);
    }

    // BASE IMPLEMENTATION
    public double calculateTotalValue() {
        double total = 0;
        for (Product p : products) {
            total += p.getPrice();
        }
        return total;
    }

    public double calculateDiscountedTotal() {
        double total = 0;
        for (Product p : products) {
            total += p.getPrice() * (1 - p.getDiscountPercent() / 100.0);
        }
        return total;
    }
}
EOF

# Modify InventoryUtils (Insert at same location as Main for conflict)
sed -i '/public static boolean isValidId/i \    public static double calculateBulkDiscount(double total, int quantity) {\n        return quantity > 10 ? total * 0.9 : total;\n    }\n' src/main/java/com/inventory/util/InventoryUtils.java

# Modify POM (Insert at same location for conflict)
sed -i '/<!-- Dependencies start here -->/a \        <dependency>\n            <groupId>org.apache.commons</groupId>\n            <artifactId>commons-math3</artifactId>\n            <version>3.6.1</version>\n        </dependency>' pom.xml

git commit -am "Feat: Add discount system support"

# 6. Trigger Merge Conflict
echo "Triggering merge conflict..."
# We are on feature/discount-system. Merge main into it.
git merge main || true

# Verify conflicts exist
if ! git status | grep -q "both modified"; then
    echo "ERROR: Setup failed to create merge conflicts!"
    exit 1
fi

# 7. Setup IntelliJ
chown -R ga:ga "$PROJECT_DIR"
setup_intellij_project "$PROJECT_DIR" "commons-inventory" 120

# Record timestamps
date +%s > /tmp/task_start_time.txt
# Copy initial failed merge state for later comparison if needed
git status > /tmp/initial_git_status.txt

# Take initial screenshot showing the conflict state (usually shows up in Project view with red files)
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="