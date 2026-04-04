#!/bin/bash
set -e
echo "=== Setting up fix_jpa_entity_mappings task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-orm"
mkdir -p "$PROJECT_DIR"

# 1. Create Project Structure
echo "Generating Spring Boot project..."

# Create directories
mkdir -p "$PROJECT_DIR/src/main/java/com/example/inventory/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/inventory/repository"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/inventory"

# POM.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>inventory-orm</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <properties>
        <java.version>17</java.version>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
            <version>3.1.5</version>
        </dependency>
        <dependency>
            <groupId>com.h2database</groupId>
            <artifactId>h2</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <version>3.1.5</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <version>3.1.5</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# Schema SQL (The Truth)
cat > "$PROJECT_DIR/src/main/resources/schema.sql" << 'EOF'
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS category;

CREATE TABLE category (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

CREATE TABLE product (
    product_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku_code VARCHAR(50) UNIQUE NOT NULL,
    unit_price DECIMAL(10,2),
    category_id BIGINT,
    FOREIGN KEY (category_id) REFERENCES category(id)
);
EOF

# Application Properties
cat > "$PROJECT_DIR/src/main/resources/application.properties" << 'EOF'
spring.datasource.url=jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1
spring.datasource.driverClassName=org.h2.Driver
spring.datasource.username=sa
spring.datasource.password=
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
# Validate schema against entities (will fail if mappings are wrong)
spring.jpa.hibernate.ddl-auto=validate
spring.sql.init.mode=always
EOF

# Main Application Class
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/InventoryApplication.java" << 'EOF'
package com.example.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class InventoryApplication {
    public static void main(String[] args) {
        SpringApplication.run(InventoryApplication.class, args);
    }
}
EOF

# Broken Entity: Category (Missing @Entity)
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/model/Category.java" << 'EOF'
package com.example.inventory.model;

import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
// MISSING @Entity annotation

public class Category {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String name;

    public Category() {}
    public Category(String name) { this.name = name; }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
}
EOF

# Broken Entity: Product (Wrong columns, wrong relationship type)
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/model/Product.java" << 'EOF'
package com.example.inventory.model;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
public class Product {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id; // DB expects product_id

    private String sku; // DB expects sku_code

    private BigDecimal price; // DB expects unit_price

    // DB expects relationship to Category, but here we just have ID
    // Task: Refactor to 'private Category category;' with @ManyToOne
    private Long categoryId;

    public Product() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getSku() { return sku; }
    public void setSku(String sku) { this.sku = sku; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Long getCategoryId() { return categoryId; }
    public void setCategoryId(Long categoryId) { this.categoryId = categoryId; }
}
EOF

# Repositories (will be used by tests)
cat > "$PROJECT_DIR/src/main/java/com/example/inventory/repository/CategoryRepository.java" << 'EOF'
package com.example.inventory.repository;
import com.example.inventory.model.Category;
import org.springframework.data.jpa.repository.JpaRepository;
public interface CategoryRepository extends JpaRepository<Category, Long> {}
EOF

cat > "$PROJECT_DIR/src/main/java/com/example/inventory/repository/ProductRepository.java" << 'EOF'
package com.example.inventory.repository;
import com.example.inventory.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
public interface ProductRepository extends JpaRepository<Product, Long> {}
EOF

# Integration Test (Fails initially)
cat > "$PROJECT_DIR/src/test/java/com/example/inventory/MappingIntegrationTest.java" << 'EOF'
package com.example.inventory;

import com.example.inventory.model.Category;
import com.example.inventory.model.Product;
import com.example.inventory.repository.CategoryRepository;
import com.example.inventory.repository.ProductRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@Transactional
public class MappingIntegrationTest {

    @Autowired private CategoryRepository categoryRepository;
    @Autowired private ProductRepository productRepository;
    @Autowired private JdbcTemplate jdbcTemplate;

    @Test
    void testSchemaMappingAndRefactoring() {
        // 1. Save a Category (Verifies @Entity on Category)
        Category cat = new Category("Electronics");
        cat = categoryRepository.save(cat);
        assertNotNull(cat.getId(), "Category ID should be generated");

        // 2. Save a Product (Verifies column mappings and relationship)
        // NOTE: The test uses reflection/introspection to adapt to the student's refactoring
        // or expects the refactoring to be done.
        
        Product p = new Product();
        
        // Try to set SKU (mapped to sku_code)
        p.setSku("TEST-123");
        p.setPrice(new BigDecimal("99.99"));

        // Handle Relationship: Agent should have refactored 'categoryId' to 'Category category'
        try {
            // Using reflection to call setCategory if it exists
            java.lang.reflect.Method setCat = Product.class.getMethod("setCategory", Category.class);
            setCat.invoke(p, cat);
        } catch (Exception e) {
            fail("Product class should have setCategory(Category) method. Did you refactor the relationship?");
        }

        p = productRepository.save(p);
        assertNotNull(p.getId(), "Product ID should be generated");

        // 3. Verify Database Columns via SQL (Source of Truth)
        // This ensures they didn't just change the schema.sql (which they shouldn't)
        // but actually mapped the entity to the existing schema.
        
        Map<String, Object> dbRow = jdbcTemplate.queryForMap(
            "SELECT * FROM product WHERE product_id = ?", p.getId());
            
        assertEquals("TEST-123", dbRow.get("SKU_CODE"), "Should map 'sku' field to 'sku_code' column");
        assertTrue(new BigDecimal("99.99").compareTo((BigDecimal)dbRow.get("UNIT_PRICE")) == 0, 
                   "Should map 'price' field to 'unit_price' column");
        
        // Verify Foreign Key column
        assertEquals(cat.getId(), dbRow.get("CATEGORY_ID"), 
                     "Should map relationship to 'category_id' column");
    }
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# 2. Record Initial State
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/main/resources/schema.sql" > /tmp/initial_schema_hash.txt

# 3. Setup IntelliJ
setup_intellij_project "$PROJECT_DIR" "inventory-orm" 120

# 4. Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="