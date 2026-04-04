#!/bin/bash
set -e
echo "=== Setting up document_menu_inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous report file to ensure clean state
rm -f /home/ga/menu_inventory_report.txt

# -----------------------------------------------------------------------------
# Extract Ground Truth from Derby Database
# -----------------------------------------------------------------------------
# We use a temporary Java utility to query the embedded Derby database
# before the agent starts interacting with it.
echo "Extracting ground truth from Derby DB..."

# Locate Database and Derby JARs
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Derby DB path: $DB_PATH"

DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" 2>/dev/null | head -1)
if [ -z "$DERBY_JAR" ]; then
    # Try finding it in lib folder
    DERBY_JAR=$(find /opt/floreantpos -name "derby*.jar" -path "*/lib/*" 2>/dev/null | head -1)
fi

if [ -z "$DERBY_JAR" ]; then
    echo "ERROR: Could not find derby.jar. Cannot extract ground truth."
    # We will fail gracefully here, but the verifier will handle missing ground truth
else
    DERBY_DIR=$(dirname "$DERBY_JAR")
    echo "Found Derby JAR at: $DERBY_JAR"

    # Create Java extractor
    cat > /tmp/ExtractMenuTruth.java << 'JAVAEOF'
import java.sql.*;
import java.io.*;

public class ExtractMenuTruth {
    public static void main(String[] args) {
        String dbPath = args[0];
        // Standard Derby embedded connection string
        String connUrl = "jdbc:derby:" + dbPath;
        
        try (Connection conn = DriverManager.getConnection(connUrl);
             Statement stmt = conn.createStatement();
             PrintWriter pw = new PrintWriter(new FileWriter("/tmp/ground_truth_menu.txt"))) {
            
            // 1. Get categories and item counts
            // Note: Schema usually separates MENU_CATEGORY and MENU_ITEM
            ResultSet rs = stmt.executeQuery(
                "SELECT mc.NAME as cat_name, COUNT(mi.ID) as item_count " +
                "FROM MENU_CATEGORY mc " +
                "LEFT JOIN MENU_ITEM mi ON mi.CATEGORY_ID = mc.ID " +
                "GROUP BY mc.NAME " +
                "ORDER BY mc.NAME"
            );
            
            int totalItems = 0;
            while (rs.next()) {
                String catName = rs.getString("cat_name");
                int count = rs.getInt("item_count");
                totalItems += count;
                pw.println("CATEGORY:" + catName + ":" + count);
            }
            rs.close();
            pw.println("TOTAL:" + totalItems);
            
            // 2. Get most expensive item
            rs = stmt.executeQuery(
                "SELECT NAME, PRICE FROM MENU_ITEM " +
                "WHERE PRICE = (SELECT MAX(PRICE) FROM MENU_ITEM) " +
                "FETCH FIRST 1 ROW ONLY"
            );
            if (rs.next()) {
                pw.println("MOST_EXPENSIVE:" + rs.getString("NAME") + ":" + rs.getDouble("PRICE"));
            }
            rs.close();
            
            // 3. Get least expensive item (price > 0)
            rs = stmt.executeQuery(
                "SELECT NAME, PRICE FROM MENU_ITEM " +
                "WHERE PRICE > 0 AND PRICE = (SELECT MIN(PRICE) FROM MENU_ITEM WHERE PRICE > 0) " +
                "FETCH FIRST 1 ROW ONLY"
            );
            if (rs.next()) {
                pw.println("LEAST_EXPENSIVE:" + rs.getString("NAME") + ":" + rs.getDouble("PRICE"));
            }
            rs.close();
            
            System.out.println("Ground truth extracted successfully.");
            
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }
}
JAVAEOF

    # Compile and run
    cd /tmp
    if javac ExtractMenuTruth.java; then
        # Run with classpath including Derby and current dir
        java -cp ".:${DERBY_DIR}/*:${DERBY_DIR}/../lib/*" ExtractMenuTruth "$DB_PATH" > /tmp/ground_truth.log 2>&1 || {
            echo "WARNING: Java execution failed"
            cat /tmp/ground_truth.log
        }
    else
        echo "WARNING: Compilation failed"
    fi
fi

# Secure ground truth file
if [ -f "/tmp/ground_truth_menu.txt" ]; then
    chmod 644 /tmp/ground_truth_menu.txt
    echo "Ground truth generated:"
    cat /tmp/ground_truth_menu.txt
else
    echo "WARNING: Ground truth file was not generated."
fi

# -----------------------------------------------------------------------------
# Start Application
# -----------------------------------------------------------------------------
# Start Floreant POS on the main terminal screen
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="