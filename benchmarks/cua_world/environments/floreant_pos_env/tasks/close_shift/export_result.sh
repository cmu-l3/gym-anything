#!/bin/bash
echo "=== Exporting Close Shift Results ==="

source /workspace/scripts/task_utils.sh

TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# 2. Check if Floreant was running (before we kill it)
APP_WAS_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# 3. Kill Floreant to release Derby DB lock
kill_floreant
sleep 3

# 4. Verify DB State using Java
# We need to check if the shift is now closed (SHIFT_END_TIME is NOT NULL)
echo "Verifying database state..."

cat > /tmp/VerifyShift.java << 'JAVAEOF'
import java.sql.*;

public class VerifyShift {
    public static void main(String[] args) {
        String dbUrl = "jdbc:derby:/opt/floreantpos/database/derby-server/posdb";
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(dbUrl);
            Statement stmt = conn.createStatement();
            
            int openShifts = 0;
            int closedShifts = 0;
            long lastCloseTime = 0;
            
            ResultSet rs = stmt.executeQuery("SELECT SHIFT_END_TIME FROM RESTAURANT_SHIFT");
            while (rs.next()) {
                Timestamp endTs = rs.getTimestamp(1);
                if (rs.wasNull() || endTs == null) {
                    openShifts++;
                } else {
                    closedShifts++;
                    if (endTs.getTime() > lastCloseTime) {
                        lastCloseTime = endTs.getTime();
                    }
                }
            }
            rs.close();
            conn.close();
            try { DriverManager.getConnection("jdbc:derby:;shutdown=true"); } catch (SQLException se) {}
            
            System.out.println("OPEN_SHIFTS=" + openShifts);
            System.out.println("CLOSED_SHIFTS=" + closedShifts);
            System.out.println("LAST_CLOSE_TIME=" + lastCloseTime);
            
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# Compile and run verifier
DERBY_CP=$(find /opt/floreantpos -name "derby*.jar" -printf "%p:" 2>/dev/null)
cd /tmp
javac -cp "$DERBY_CP" VerifyShift.java
java -cp ".:$DERBY_CP" VerifyShift > /tmp/verify_output.txt 2>&1

# Parse output
OPEN_SHIFTS=$(grep "OPEN_SHIFTS=" /tmp/verify_output.txt | cut -d= -f2)
LAST_CLOSE_TIME_MS=$(grep "LAST_CLOSE_TIME=" /tmp/verify_output.txt | cut -d= -f2)

# Calculate if close happened during task
# Convert task start to ms
TASK_START_MS=$((TASK_START_TIME * 1000))
CLOSED_DURING_TASK="false"

if [ -n "$LAST_CLOSE_TIME_MS" ] && [ "$LAST_CLOSE_TIME_MS" -gt "$TASK_START_MS" ]; then
    CLOSED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIME,
    "task_end": $TASK_END_TIME,
    "app_was_running": $APP_WAS_RUNNING,
    "open_shifts_count": ${OPEN_SHIFTS:-999},
    "closed_during_task": $CLOSED_DURING_TASK,
    "last_close_timestamp": ${LAST_CLOSE_TIME_MS:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="