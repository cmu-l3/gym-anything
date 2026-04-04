#!/bin/bash
set -e
echo "=== Setting up fix_concurrency_race_condition task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-system"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create Maven Project Structure
su - ga -c "mkdir -p $PROJECT_DIR/src/main/java/com/store/inventory"
su - ga -c "mkdir -p $PROJECT_DIR/src/test/java/com/store/inventory"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.store</groupId>
  <artifactId>inventory-system</artifactId>
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
  </dependencies>
</project>
EOF
chown ga:ga "$PROJECT_DIR/pom.xml"

# 3. Create the buggy InventoryService.java
cat > "$PROJECT_DIR/src/main/java/com/store/inventory/InventoryService.java" << 'EOF'
package com.store.inventory;

import java.util.HashMap;
import java.util.Map;

public class InventoryService {
    // Stores product ID -> quantity
    private final Map<String, Integer> stock = new HashMap<>();

    public void addStock(String productId, int quantity) {
        stock.put(productId, stock.getOrDefault(productId, 0) + quantity);
    }

    public int getStock(String productId) {
        return stock.getOrDefault(productId, 0);
    }

    /**
     * Attempts to reserve stock for a product.
     * Returns true if stock was successfully reserved, false otherwise.
     */
    public boolean reserveStock(String productId, int quantity) {
        // BUG: This read-modify-write is not atomic
        int currentStock = stock.getOrDefault(productId, 0);
        
        if (currentStock >= quantity) {
            // Simulate slight processing delay to exacerbate race condition
            try { Thread.sleep(1); } catch (InterruptedException e) {}
            
            stock.put(productId, currentStock - quantity);
            return true;
        }
        return false;
    }
}
EOF
chown ga:ga "$PROJECT_DIR/src/main/java/com/store/inventory/InventoryService.java"

# 4. Create the concurrency test
cat > "$PROJECT_DIR/src/test/java/com/store/inventory/InventoryConcurrencyTest.java" << 'EOF'
package com.store.inventory;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public class InventoryConcurrencyTest {

    @Test
    public void testConcurrentReservations() throws InterruptedException {
        InventoryService inventoryService = new InventoryService();
        int initialStock = 100;
        inventoryService.addStock("item-1", initialStock);
        
        // We will spawn more threads than stock available
        int numberOfThreads = 200;
        
        CountDownLatch startLatch = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(numberOfThreads);
        AtomicInteger successfulReservations = new AtomicInteger(0);

        for (int i = 0; i < numberOfThreads; i++) {
            executor.submit(() -> {
                try { 
                    startLatch.await(); // Wait for signal to start all at once
                    if (inventoryService.reserveStock("item-1", 1)) {
                        successfulReservations.incrementAndGet();
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        
        startLatch.countDown(); // Start all threads
        executor.shutdown();
        executor.awaitTermination(5, TimeUnit.SECONDS);

        System.out.println("Initial Stock: " + initialStock);
        System.out.println("Successful Reservations: " + successfulReservations.get());
        System.out.println("Remaining Stock in DB: " + inventoryService.getStock("item-1"));

        // Assertions
        // 1. We should not have sold more items than existed
        assertTrue("Sold more items (" + successfulReservations.get() + ") than initial stock (" + initialStock + ")", 
                   successfulReservations.get() <= initialStock);
                   
        // 2. The remaining stock should be exactly Initial - Sold
        assertEquals("Stock calculation mismatch", 
                     initialStock - successfulReservations.get(), 
                     inventoryService.getStock("item-1"));
                     
        // 3. In this specific scenario (200 requests for 100 items), we expect to sell out exactly 100
        // (Assuming the fix is correct and efficient enough)
        assertEquals("Should have sold exactly all stock", initialStock, successfulReservations.get());
        assertEquals("Stock should be zero", 0, inventoryService.getStock("item-1"));
    }
}
EOF
chown ga:ga "$PROJECT_DIR/src/test/java/com/store/inventory/InventoryConcurrencyTest.java"

# Record initial timestamps and checksums
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/main/java/com/store/inventory/InventoryService.java" > /tmp/initial_source_hash.txt
md5sum "$PROJECT_DIR/src/test/java/com/store/inventory/InventoryConcurrencyTest.java" > /tmp/initial_test_hash.txt

# Open IntelliJ
echo "Launching IntelliJ with project..."
setup_intellij_project "$PROJECT_DIR" "inventory-system" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="