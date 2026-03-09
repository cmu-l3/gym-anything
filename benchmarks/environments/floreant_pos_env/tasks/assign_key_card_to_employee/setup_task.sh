#!/bin/bash
set -e
echo "=== Setting up assign_key_card_to_employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Floreant instance to unlock DB
kill_floreant
sleep 2

# Restore clean database from backup
echo "Restoring clean database..."
DB_LIVE_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -d "/opt/floreantpos/posdb_backup" ] && [ -n "$DB_LIVE_DIR" ]; then
    rm -rf "$DB_LIVE_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_LIVE_DIR"
    chown -R ga:ga "$DB_LIVE_DIR"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
fi

# --------------------------------------------------------------------------
# Inject "John Doe" User into Derby DB using a temporary Java utility
# --------------------------------------------------------------------------
echo "Injecting target user 'John Doe' into database..."

cat > /tmp/InjectUser.java << 'JAVAEOF'
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;

public class InjectUser {
    public static void main(String[] args) {
        String dbURL = "jdbc:derby:/opt/floreantpos/database/derby-server/posdb";
        
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(dbURL);
            
            // Check if user exists
            PreparedStatement checkStmt = conn.prepareStatement("SELECT ID FROM USERS WHERE FIRST_NAME = ? AND LAST_NAME = ?");
            checkStmt.setString(1, "John");
            checkStmt.setString(2, "Doe");
            ResultSet rs = checkStmt.executeQuery();
            
            if (rs.next()) {
                // Reset secret key if exists
                System.out.println("User John Doe exists. Resetting secret key...");
                PreparedStatement updateStmt = conn.prepareStatement("UPDATE USERS SET SECRET_KEY = NULL WHERE FIRST_NAME = ? AND LAST_NAME = ?");
                updateStmt.setString(1, "John");
                updateStmt.setString(2, "Doe");
                updateStmt.executeUpdate();
            } else {
                // Create user
                System.out.println("Creating new user John Doe...");
                // Note: Schema varies slightly by version, we try a standard insert for Floreant 1.4
                // ID (Auto-inc or manual), ACTIVE, COST_PER_HOUR, FIRST_NAME, LAST_NAME, PASSWORD, USER_TYPE
                // We use a high ID (9999) to avoid conflicts if auto-inc isn't strictly enforced
                String insertSQL = "INSERT INTO USERS (ID, ACTIVE, COST_PER_HOUR, FIRST_NAME, LAST_NAME, PASSWORD, USER_TYPE) VALUES (9999, 1, 15.0, 'John', 'Doe', '1234', 2)";
                Statement stmt = conn.createStatement();
                stmt.executeUpdate(insertSQL);
            }
            
            conn.close();
            System.out.println("Injection complete.");
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }
}
JAVAEOF

# Compile and run the injector
DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" | head -1)
if [ -z "$DERBY_JAR" ]; then
     DERBY_JAR="/opt/floreantpos/lib/derby.jar"
fi

if [ -f "$DERBY_JAR" ]; then
    cd /tmp
    /usr/lib/jvm/java-11-openjdk-amd64/bin/javac InjectUser.java
    /usr/lib/jvm/java-11-openjdk-amd64/bin/java -cp ".:$DERBY_JAR" InjectUser
else
    echo "WARNING: Derby jar not found, skipping injection. Task may fail if John Doe missing."
fi

# Launch Floreant POS
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="