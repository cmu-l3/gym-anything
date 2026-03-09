#!/bin/bash
echo "=== Exporting create_menu_group results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Check if app was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Kill Floreant POS to release DB lock (Derby embedded mode locks the DB)
kill_floreant

# 4. Query Derby Database
# We need to compile a small Java program to check the DB because ij might not be in path
# and we need to use the jars provided with Floreant.

echo "Compiling DB verification tool..."

# Locate Derby jars
DERBY_LIB_DIR="/opt/floreantpos/lib"
DERBY_JAR=$(find "$DERBY_LIB_DIR" -name "derby.jar" | head -1)
# Some distributions put it in a different spot, try root if not in lib
if [ -z "$DERBY_JAR" ]; then
    DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" | head -1)
fi

if [ -z "$DERBY_JAR" ]; then
    echo "ERROR: Could not find derby.jar"
    DB_CHECK_RESULT="error_no_jar"
else
    # Create temporary Java source
    cat > /tmp/CheckGroup.java << 'JAVAEOF'
import java.sql.*;
import java.util.Properties;

public class CheckGroup {
    public static void main(String[] args) {
        // Floreant default DB path
        String dbPath = "/opt/floreantpos/database/derby-server/posdb";
        String url = "jdbc:derby:" + dbPath;
        
        try {
            // Load driver (embedded)
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            
            try (Connection conn = DriverManager.getConnection(url);
                 Statement stmt = conn.createStatement()) {
                
                // Query for the specific group
                // Note: Column names based on standard Floreant schema
                ResultSet rs = stmt.executeQuery(
                    "SELECT ID, NAME, VISIBLE FROM MENU_GROUP WHERE UPPER(NAME) = 'BREAKFAST SPECIALS'"
                );
                
                if (rs.next()) {
                    System.out.println("FOUND=true");
                    System.out.println("NAME=" + rs.getString("NAME"));
                    // Try to get category info if possible, though schema varies. 
                    // Just existence is the primary check.
                } else {
                    System.out.println("FOUND=false");
                }
                
            } catch (SQLException e) {
                e.printStackTrace();
                System.out.println("ERROR=" + e.getMessage());
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.out.println("ERROR=" + e.getMessage());
        }
    }
}
JAVAEOF

    # Compile and run
    echo "Running DB check..."
    javac -cp "$DERBY_JAR" /tmp/CheckGroup.java
    
    # Run and capture output
    DB_OUTPUT=$(java -cp ".:$DERBY_JAR" -Dderby.system.home="/opt/floreantpos/database" CheckGroup)
    echo "$DB_OUTPUT"
    
    # Parse output
    if echo "$DB_OUTPUT" | grep -q "FOUND=true"; then
        RECORD_FOUND="true"
        RECORD_NAME=$(echo "$DB_OUTPUT" | grep "NAME=" | cut -d'=' -f2)
    else
        RECORD_FOUND="false"
        RECORD_NAME=""
    fi
fi

# 5. Create JSON result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_record_found": $RECORD_FOUND,
    "db_record_name": "$RECORD_NAME",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="