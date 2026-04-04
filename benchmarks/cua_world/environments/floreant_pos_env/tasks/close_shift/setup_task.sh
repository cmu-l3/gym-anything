#!/bin/bash
set -e
echo "=== Setting up Close Shift Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing Floreant instances to release DB lock
kill_floreant
sleep 2

# 2. Restore clean DB to ensure known state
echo "Restoring clean database state..."
DB_DIR="/opt/floreantpos/database/derby-server"
BACKUP_DIR="/opt/floreantpos/derby_server_backup"
POSDB_BACKUP="/opt/floreantpos/posdb_backup"

if [ -d "$POSDB_BACKUP" ]; then
    # If we have a direct backup of the posdb folder
    TARGET_DB=$(find "$DB_DIR" -name "service.properties" 2>/dev/null | head -1 | xargs dirname)
    if [ -n "$TARGET_DB" ]; then
        rm -rf "$TARGET_DB"
        cp -r "$POSDB_BACKUP" "$TARGET_DB"
        chown -R ga:ga "$TARGET_DB"
    fi
elif [ -d "$BACKUP_DIR" ]; then
    # Fallback to full derby-server backup
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
fi

# 3. Programmatically OPEN a shift in the Derby DB
# We do this via Java because UI automation is flaky for setup and we need 100% certainty a shift is open.
echo "Injecting open shift into database..."

cat > /tmp/OpenShift.java << 'JAVAEOF'
import java.sql.*;
import java.util.Date;

public class OpenShift {
    public static void main(String[] args) {
        String dbUrl = "jdbc:derby:/opt/floreantpos/database/derby-server/posdb";
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(dbUrl);
            Statement stmt = conn.createStatement();
            
            // 1. Check if an open shift already exists
            // Floreant typically uses RESTAURANT_SHIFT or SHIFT table
            // We'll look for SHIFT_END_TIME IS NULL
            boolean openShiftExists = false;
            try {
                ResultSet rs = stmt.executeQuery("SELECT ID FROM RESTAURANT_SHIFT WHERE SHIFT_END_TIME IS NULL");
                if (rs.next()) {
                    System.out.println("OPEN_SHIFT_EXISTS_ID:" + rs.getInt(1));
                    openShiftExists = true;
                }
                rs.close();
            } catch (SQLException e) {
                // Table might be named differently in some versions, but RESTAURANT_SHIFT is standard
                System.out.println("Table check error: " + e.getMessage());
            }

            // 2. If no open shift, insert one
            if (!openShiftExists) {
                // Get max ID
                int newId = 1;
                try {
                    ResultSet rs = stmt.executeQuery("SELECT MAX(ID) FROM RESTAURANT_SHIFT");
                    if (rs.next()) newId = rs.getInt(1) + 1;
                    rs.close();
                } catch (Exception e) {}

                long now = System.currentTimeMillis();
                Timestamp startTs = new Timestamp(now);
                
                // Insert
                PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO RESTAURANT_SHIFT (ID, SHIFT_START_TIME, SHIFT_OPEN_AMOUNT, TERMINAL_ID, USER_ID) " +
                    "VALUES (?, ?, 100.00, 1, 1)" 
                    // Assuming Terminal 1 and User 1 (Admin/Manager) exist in default DB
                );
                ps.setInt(1, newId);
                ps.setTimestamp(2, startTs);
                ps.executeUpdate();
                ps.close();
                System.out.println("CREATED_OPEN_SHIFT_ID:" + newId);
            }
            
            conn.close();
            try { DriverManager.getConnection("jdbc:derby:;shutdown=true"); } catch (SQLException se) {}
            
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }
}
JAVAEOF

# Compile and run
DERBY_CP=$(find /opt/floreantpos -name "derby*.jar" -printf "%p:" 2>/dev/null)
cd /tmp
javac -cp "$DERBY_CP" OpenShift.java
java -cp ".:$DERBY_CP" OpenShift > /tmp/openshift_log.txt 2>&1 || echo "Java execution failed"
cat /tmp/openshift_log.txt

# Record initial count of open shifts (should be 1)
echo "1" > /tmp/initial_open_shift_count.txt

# 4. Start Floreant POS
echo "Starting Floreant POS..."
start_and_login
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="