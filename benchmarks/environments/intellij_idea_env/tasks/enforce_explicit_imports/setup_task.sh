#!/bin/bash
set -e
echo "=== Setting up enforce_explicit_imports task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-system"
mkdir -p "$PROJECT_DIR/src/main/java/com/inventory/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/inventory/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/inventory/util"

# 1. Create Maven POM
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.inventory</groupId>
  <artifactId>inventory-system</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <!-- Common logging to ensure imports are needed -->
    <dependency>
        <groupId>java.util.logging</groupId>
        <artifactId>logging-api</artifactId>
        <version>1.0.0</version>
        <scope>provided</scope>
    </dependency>
  </dependencies>
</project>
POMEOF

# 2. Create Java files WITH WILDCARD IMPORTS

# File 1: Product.java (Model)
cat > "$PROJECT_DIR/src/main/java/com/inventory/model/Product.java" << 'JAVAEOF'
package com.inventory.model;

import java.io.*;
import java.util.*;
import java.math.*;

public class Product implements Serializable {
    private String id;
    private String name;
    private BigDecimal price;
    private Date dateAdded;
    private List<String> tags;

    public Product(String id, String name, double price) {
        this.id = id;
        this.name = name;
        this.price = new BigDecimal(price);
        this.dateAdded = new Date();
        this.tags = new ArrayList<>();
    }

    public void addTag(String tag) {
        tags.add(tag);
    }

    public List<String> getTags() {
        return Collections.unmodifiableList(tags);
    }
}
JAVAEOF

# File 2: InventoryService.java (Service)
cat > "$PROJECT_DIR/src/main/java/com/inventory/service/InventoryService.java" << 'JAVAEOF'
package com.inventory.service;

import com.inventory.model.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.*;

public class InventoryService {
    private Map<String, Product> inventory = new ConcurrentHashMap<>();
    private List<String> transactionLog = new ArrayList<>();

    public void addProduct(Product p) {
        inventory.put(UUID.randomUUID().toString(), p);
    }

    public List<Product> search(String query) {
        return inventory.values().stream()
                .filter(p -> p.toString().contains(query))
                .collect(Collectors.toList());
    }

    public Set<String> getAllIds() {
        return new HashSet<>(inventory.keySet());
    }
}
JAVAEOF

# File 3: FileUtils.java (Util)
cat > "$PROJECT_DIR/src/main/java/com/inventory/util/FileUtils.java" << 'JAVAEOF'
package com.inventory.util;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class FileUtils {
    public static void saveToFile(List<String> lines, String path) throws IOException {
        Path p = Paths.get(path);
        Files.write(p, lines);
    }

    public static List<String> readLines(String path) throws IOException {
        File f = new File(path);
        if (!f.exists()) return Collections.emptyList();
        
        try (BufferedReader reader = new BufferedReader(new FileReader(f))) {
            List<String> result = new ArrayList<>();
            String line;
            while ((line = reader.readLine()) != null) {
                result.add(line);
            }
            return result;
        }
    }
}
JAVAEOF

chown -R ga:ga "$PROJECT_DIR"

# 3. Record initial state (timestamps and content hash)
date +%s > /tmp/task_start_time.txt
find "$PROJECT_DIR/src" -name "*.java" -exec md5sum {} + > /tmp/initial_file_hashes.txt

# 4. Open Project in IntelliJ
echo "Opening project in IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "inventory-system" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="