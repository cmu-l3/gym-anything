#!/bin/bash
set -e
echo "=== Setting up task: update_restaurant_info ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running Floreant POS to access the DB for baseline capture
kill_floreant
sleep 2

# 2. Locate Database and Derby JAR
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    DB_DIR="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Derby DB at: $DB_DIR"
echo "$DB_DIR" > /tmp/floreant_db_path.txt

DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" -type f 2>/dev/null | head -1)
if [ -z "$DERBY_JAR" ]; then
    # Fallback search
    DERBY_JAR=$(find /opt/floreantpos -name "derby-*.jar" -type f 2>/dev/null | head -1)
fi
echo "Derby JAR: $DERBY_JAR"
echo "$DERBY_JAR" > /tmp/floreant_derby_jar.txt

# 3. Create Java Tool to Query Restaurant Table
# We embed this here to ensure it compiles with the environment's Java version
cat > /tmp/QueryRestaurant.java << 'JAVAEOF'
import java.sql.*;
import java.util.Properties;

public class QueryRestaurant {
    public static void main(String[] args) {
        String dbPath = args[0];
        Connection conn = null;
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            conn = DriverManager.getConnection("jdbc:derby:" + dbPath);
            Statement stmt = conn.createStatement();
            
            // Try different possible table names if schema varies, but standard is RESTAURANT
            ResultSet rs = stmt.executeQuery("SELECT * FROM RESTAURANT");
            ResultSetMetaData md = rs.getMetaData();
            
            if (rs.next()) {
                // Iterate columns and print key=value
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    String colName = md.getColumnName(i).toUpperCase();
                    String val = rs.getString(i);
                    if (val == null) val = "";
                    System.out.println(colName + "=" + val.trim());
                }
            } else {
                System.out.println("ERROR: No rows in RESTAURANT table");
            }
            rs.close();
            stmt.close();
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        } finally {
            if (conn != null) {
                try { conn.close(); } catch (Exception e) {}
            }
            // Shutdown Derby to release lock cleanly
            try {
                DriverManager.getConnection("jdbc:derby:;shutdown=true");
            } catch (SQLException e) {
                // Expected: Derby always throws on shutdown
            }
        }
    }
}
JAVAEOF

# 4. Compile the query tool
if [ -f "$DERBY_JAR" ]; then
    echo "Compiling query tool..."
    javac -cp "$DERBY_JAR" /tmp/QueryRestaurant.java -d /tmp/
else
    echo "ERROR: Could not find derby.jar"
fi

# 5. Capture Baseline Data
echo "Capturing baseline restaurant info..."
if [ -f /tmp/QueryRestaurant.class ]; then
    # Remove any stale locks
    rm -f "$DB_DIR/db.lck" 2>/dev/null || true
    
    java -cp "/tmp:$DERBY_JAR" QueryRestaurant "$DB_DIR" > /tmp/restaurant_baseline.txt 2>/dev/null || echo "Query failed"
else
    echo "Baseline capture skipped (compilation failed)"
    touch /tmp/restaurant_baseline.txt
fi

echo "Baseline Data:"
cat /tmp/restaurant_baseline.txt

# 6. Start Floreant POS for the agent
echo "Starting Floreant POS..."
start_and_login

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="