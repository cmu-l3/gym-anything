#!/bin/bash
echo "=== Setting up Rename Terminal task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing instances
kill_floreant

# 2. Restore clean database to ensure known starting state
echo "Restoring clean database snapshot..."
# Find where the active DB is
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    # Fallback default
    DB_DIR="/opt/floreantpos/database/derby-server"
fi

# Restore from backup if exists
if [ -d "/opt/floreantpos/posdb_backup" ]; then
    rm -rf "$DB_DIR"
    mkdir -p "$(dirname "$DB_DIR")"
    cp -r "/opt/floreantpos/posdb_backup" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from /opt/floreantpos/posdb_backup"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    rm -rf "$DB_DIR"
    mkdir -p "$(dirname "$DB_DIR")"
    cp -r "/opt/floreantpos/derby_server_backup" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from /opt/floreantpos/derby_server_backup"
fi

# 3. Capture initial terminal name for comparison (using temporary Java query)
# Note: We can only query when app is NOT running due to Derby lock
echo "Reading initial terminal name..."
cat > /tmp/GetTerminalName.java << 'EOF'
import java.sql.*;
public class GetTerminalName {
    public static void main(String[] args) {
        String dbPath = args[0];
        String url = "jdbc:derby:" + dbPath;
        try (Connection conn = DriverManager.getConnection(url);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT NAME FROM TERMINAL")) {
            if (rs.next()) {
                System.out.println(rs.getString(1));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
EOF

# Compile and run
javac /tmp/GetTerminalName.java
# Construct classpath: usually /opt/floreantpos/lib contains derby.jar
CP=".:/opt/floreantpos/floreantpos.jar:/opt/floreantpos/lib/*"
INITIAL_NAME=$(java -cp "$CP" GetTerminalName "$DB_DIR")
echo "$INITIAL_NAME" > /tmp/initial_terminal_name.txt
echo "Initial Terminal Name: $INITIAL_NAME"

# 4. Launch Floreant POS
start_and_login

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="