#!/bin/bash
set -e

echo "=== Setting up Refactor Change Signature Task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
PROJECT_DIR="/home/ga/IdeaProjects/warehouse-system"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/logistics/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/logistics/client"
mkdir -p "$PROJECT_DIR/src/test/java/com/logistics"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.logistics</groupId>
    <artifactId>warehouse-system</artifactId>
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

# 2. InventoryService (The Target)
cat > "$PROJECT_DIR/src/main/java/com/logistics/service/InventoryService.java" << 'EOF'
package com.logistics.service;

import java.util.HashMap;
import java.util.Map;

public class InventoryService {
    private final Map<String, Integer> stockLevels = new HashMap<>();

    public InventoryService() {
        stockLevels.put("SKU-1001", 50);
        stockLevels.put("SKU-1002", 15);
        stockLevels.put("SKU-9999", 0);
    }

    /**
     * Checks if enough stock is available.
     * TODO: Refactor this to support multiple warehouses.
     */
    public boolean checkStock(String sku, int quantity) {
        if (sku == null || quantity <= 0) {
            return false;
        }
        return stockLevels.getOrDefault(sku, 0) >= quantity;
    }

    public void addStock(String sku, int amount) {
        stockLevels.merge(sku, amount, Integer::sum);
    }
}
EOF

# 3. OrderProcessor (Caller 1)
cat > "$PROJECT_DIR/src/main/java/com/logistics/client/OrderProcessor.java" << 'EOF'
package com.logistics.client;

import com.logistics.service.InventoryService;

public class OrderProcessor {
    private final InventoryService inventory;

    public OrderProcessor(InventoryService inventory) {
        this.inventory = inventory;
    }

    public void processOrder(String orderId, String sku, int count) {
        System.out.println("Processing order " + orderId);
        
        // This call needs to be updated by the refactoring
        boolean available = inventory.checkStock(sku, count);
        
        if (available) {
            System.out.println("Stock confirmed for " + sku);
        } else {
            System.out.println("Backorder required for " + sku);
        }
    }
}
EOF

# 4. RestockJob (Caller 2)
cat > "$PROJECT_DIR/src/main/java/com/logistics/client/RestockJob.java" << 'EOF'
package com.logistics.client;

import com.logistics.service.InventoryService;

public class RestockJob {
    public void runDailyCheck(InventoryService service) {
        String[] criticalItems = {"SKU-1001", "SKU-1002"};
        
        for (String item : criticalItems) {
            if (!service.checkStock(item, 10)) {
                System.out.println("ALERT: Low stock for " + item);
            }
        }
    }
}
EOF

# 5. AdminDashboard (Caller 3)
cat > "$PROJECT_DIR/src/main/java/com/logistics/client/AdminDashboard.java" << 'EOF'
package com.logistics.client;

import com.logistics.service.InventoryService;

public class AdminDashboard {
    private InventoryService svc = new InventoryService();

    public String getStatus(String sku) {
        return svc.checkStock(sku, 1) ? "In Stock" : "Out of Stock";
    }
}
EOF

# 6. Test (Caller 4)
cat > "$PROJECT_DIR/src/test/java/com/logistics/InventoryTest.java" << 'EOF'
package com.logistics;

import com.logistics.service.InventoryService;
import org.junit.Test;
import static org.junit.Assert.*;

public class InventoryTest {
    @Test
    public void testStockCheck() {
        InventoryService service = new InventoryService();
        assertTrue("Should have stock", service.checkStock("SKU-1001", 5));
        assertFalse("Should not have stock", service.checkStock("SKU-9999", 1));
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial file checksums
md5sum "$PROJECT_DIR/src/main/java/com/logistics/service/InventoryService.java" > /tmp/initial_checksums.txt

# Start IntelliJ
setup_intellij_project "$PROJECT_DIR" "warehouse-system" 120

# Open InventoryService.java explicitly
su - ga -c "DISPLAY=:1 /opt/idea/bin/idea.sh '$PROJECT_DIR/src/main/java/com/logistics/service/InventoryService.java' &"
sleep 5

# Final UI stabilization
focus_intellij_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="