#!/bin/bash
echo "=== Exporting Rename Terminal results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Check if App was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Kill Floreant POS to release database lock
echo "Closing Floreant POS to check database..."
kill_floreant
sleep 3

# 4. Locate Database
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    DB_DIR="/opt/floreantpos/database/derby-server"
fi

# 5. check DB file modification time (Anti-gaming)
# Check 'seg0' directory which usually contains data segments
DB_MODIFIED="false"
LAST_MOD_TIME=0
if [ -d "$DB_DIR/seg0" ]; then
    # Get newest file timestamp in the DB directory
    LAST_MOD_TIME=$(find "$DB_DIR" -type f -printf '%T@\n' | sort -n | tail -1 | cut -d. -f1)
    if [ "$LAST_MOD_TIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

# 6. Query Database for Terminal Name
echo "Querying final terminal name..."
# Reuse the Java class from setup or recreate it
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

javac /tmp/GetTerminalName.java
CP=".:/opt/floreantpos/floreantpos.jar:/opt/floreantpos/lib/*"
FINAL_NAME=$(java -cp "$CP" GetTerminalName "$DB_DIR" | tr -d '\r\n')
INITIAL_NAME=$(cat /tmp/initial_terminal_name.txt 2>/dev/null || echo "")

echo "Final Terminal Name: '$FINAL_NAME'"

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_modified": $DB_MODIFIED,
    "initial_terminal_name": "$INITIAL_NAME",
    "final_terminal_name": "$FINAL_NAME",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="