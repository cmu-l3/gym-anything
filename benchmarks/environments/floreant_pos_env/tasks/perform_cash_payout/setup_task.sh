#!/bin/bash
echo "=== Setting up perform_cash_payout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance to release DB lock
kill_floreant

# 2. Restore clean database (ensure consistent starting state)
# This prevents previous task data from interfering with ID counts
if [ -d /opt/floreantpos/posdb_backup ]; then
    echo "Restoring clean database..."
    DB_DIR=$(dirname $(find /opt/floreantpos/database -name "service.properties" | head -1))
    rm -rf "$DB_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
fi

# 3. Record initial database state (Max Transaction ID)
# We need to compile a small Java tool to query Derby since 'ij' might not be in path
echo "Compiling DB query tool..."
mkdir -p /tmp/java_tools
cat > /tmp/java_tools/GetMaxID.java << 'EOF'
import java.sql.*;
public class GetMaxID {
    public static void main(String[] args) {
        try {
            String url = "jdbc:derby:/opt/floreantpos/database/derby-server";
            Connection conn = DriverManager.getConnection(url);
            Statement stmt = conn.createStatement();
            // Try to get max ID from TRANSACTIONS table
            ResultSet rs = stmt.executeQuery("SELECT MAX(ID) FROM TRANSACTIONS");
            if (rs.next()) {
                System.out.println(rs.getInt(1));
            } else {
                System.out.println("0");
            }
            conn.close();
        } catch (Exception e) {
            // Table might not exist or other error, return 0
            System.out.println("0");
        }
    }
}
EOF

# Find Floreant libs for classpath
LIB_CP=$(find /opt/floreantpos/lib -name "*.jar" | tr '\n' ':')
FLOREANT_CP="/opt/floreantpos/floreantpos.jar:$LIB_CP"

# Compile and run
javac -cp "$FLOREANT_CP" /tmp/java_tools/GetMaxID.java
MAX_ID=$(java -cp ".:/tmp/java_tools:$FLOREANT_CP" GetMaxID)
echo "$MAX_ID" > /tmp/initial_max_id.txt
echo "Initial Max Transaction ID: $MAX_ID"

# 4. Start Floreant POS
start_and_login

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="