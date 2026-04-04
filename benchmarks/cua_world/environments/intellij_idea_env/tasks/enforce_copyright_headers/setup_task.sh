#!/bin/bash
echo "=== Setting up enforce_copyright_headers task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-service"

# 1. Clean up previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/example/inventory/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/inventory/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/inventory/controller"

# 2. Generate Maven Project Structure
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>inventory-service</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
EOF

# 3. Generate Java Source Files (WITHOUT HEADERS)

# Main Application
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/InventoryApplication.java" << 'EOF'
package com.example.inventory;

public class InventoryApplication {
    public static void main(String[] args) {
        System.out.println("Inventory Service Starting...");
    }
}
EOF

# Model
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/model/Product.java" << 'EOF'
package com.example.inventory.model;

import java.math.BigDecimal;

public class Product {
    private Long id;
    private String name;
    private BigDecimal price;

    public Product(Long id, String name, BigDecimal price) {
        this.id = id;
        this.name = name;
        this.price = price;
    }

    // Getters and Setters omitted for brevity
}
EOF

# Service
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/service/InventoryService.java" << 'EOF'
package com.example.inventory.service;

import com.example.inventory.model.Product;
import java.util.ArrayList;
import java.util.List;

public class InventoryService {
    private final List<Product> products = new ArrayList<>();

    public void addProduct(Product product) {
        products.add(product);
    }

    public List<Product> getAllProducts() {
        return new ArrayList<>(products);
    }
}
EOF

# Controller
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/controller/ProductController.java" << 'EOF'
package com.example.inventory.controller;

import com.example.inventory.service.InventoryService;
import com.example.inventory.model.Product;

public class ProductController {
    private final InventoryService service;

    public ProductController(InventoryService service) {
        this.service = service;
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 4. Record initial state (timestamps for anti-gaming)
date +%s > /tmp/task_start_time.txt
find "$PROJECT_DIR" -name "*.java" -exec md5sum {} + > /tmp/initial_file_hashes.txt

# 5. Open Project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "inventory-service" 120

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="