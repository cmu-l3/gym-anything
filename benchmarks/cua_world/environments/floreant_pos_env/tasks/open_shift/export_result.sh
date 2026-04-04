#!/bin/bash
echo "=== Exporting open_shift result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check Database Modification
# Since we can't easily query Derby without complex Java setup, we use file timestamps as a proxy
# for "Database Activity" and VLM for "Correct Action".
# Ideally, we would run a Java query here, but environment constraints (classpath) make it flaky.
# We will check if the Seg0 directory (data files) was modified after task start.

DB_DIR="/opt/floreantpos/database/derby-server"
DB_MODIFIED="false"

# Find the most recently modified file in the DB directory
LATEST_DB_FILE=$(find "$DB_DIR" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
if [ -n "$LATEST_DB_FILE" ]; then
    LATEST_TIMESTAMP=$(echo "$LATEST_DB_FILE" | cut -d' ' -f1 | cut -d'.' -f1)
    if [ "$LATEST_TIMESTAMP" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
        echo "Database modification detected."
    else
        echo "No database modification detected since task start."
    fi
else
    echo "No database files found."
fi

# 4. Attempt to verify Shift using a temporary Java utility
# This is "best effort" - if it fails, we fall back to DB_MODIFIED + VLM
echo "Attempting programmatic DB verification..."

cat > /tmp/VerifyShift.java << 'JAVAEOF'
import java.sql.*;
import java.util.Properties;
import java.io.File;

public class VerifyShift {
    public static void main(String[] args) {
        String dbPath = "/opt/floreantpos/database/derby-server";
        String jdbcUrl = "jdbc:derby:" + dbPath;
        long startTime = Long.parseLong(args[0]) * 1000; // convert sec to ms
        
        // Output JSON structure
        System.out.print("{");
        
        try {
            // Try to load embedded driver
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(jdbcUrl);
            Statement stmt = conn.createStatement();
            
            // Query for shifts created after start time
            // Note: Floreant SHIFT table structure usually has START_TIME (timestamp) and OPENING_BALANCE (double)
            // We select the most recent shift
            ResultSet rs = stmt.executeQuery("SELECT ID, START_TIME, OPEN_TIME, OPENING_BALANCE, CLOSED_TIME FROM SHIFT ORDER BY ID DESC FETCH FIRST 1 ROWS ONLY");
            
            if (rs.next()) {
                int id = rs.getInt("ID");
                // Timestamps in Derby/Java might be diff format, assuming milliseconds or standard SQL timestamp
                Timestamp openTime = rs.getTimestamp("OPEN_TIME"); // or START_TIME
                long openTimeMillis = (openTime != null) ? openTime.getTime() : 0;
                
                double balance = rs.getDouble("OPENING_BALANCE");
                Timestamp closeTime = rs.getTimestamp("CLOSED_TIME");
                boolean isClosed = (closeTime != null);
                
                System.out.print("\"shift_found\": true,");
                System.out.print("\"shift_id\": " + id + ",");
                System.out.print("\"opening_balance\": " + balance + ",");
                System.out.print("\"is_closed\": " + isClosed + ",");
                System.out.print("\"shift_timestamp\": " + openTimeMillis);
            } else {
                System.out.print("\"shift_found\": false");
            }
            
            conn.close();
        } catch (Exception e) {
            System.out.print("\"error\": \"" + e.getMessage().replace("\"", "'") + "\",");
            System.out.print("\"shift_found\": false");
        }
        
        System.out.println("}");
    }
}
JAVAEOF

# Compile and Run
# Find Derby jars
DERBY_JARS=$(find /opt/floreantpos/lib -name "derby*.jar" | tr '\n' ':')
CLASSPATH=".:$DERBY_JARS"

cd /tmp
javac -cp "$CLASSPATH" VerifyShift.java 2>/dev/null
if [ -f "VerifyShift.class" ]; then
    # Run verification (pass task start timestamp)
    # We must run as 'ga' if 'ga' owns the DB files and lock file
    # But export_result runs as root. We need to be careful about file locks.
    # If the app is running, EmbeddedDriver might fail due to lock.
    # So we MUST kill the app before checking DB if using Embedded mode.
    
    kill_floreant
    
    # Now run query
    DB_RESULT=$(java -cp "$CLASSPATH" VerifyShift "$TASK_START")
    echo "DB Verification Result: $DB_RESULT"
else
    echo "Failed to compile DB verifier. CLASSPATH: $CLASSPATH"
    DB_RESULT="{ \"shift_found\": false, \"error\": \"Compilation failed\" }"
fi

# 5. Check if App was running (before we killed it)
# (We killed it above for DB check, so we check process list from earlier or just assume)
# To be safe, let's assume if DB check runs, we killed it intentionally. 
# We'll rely on screenshots for "app was running" proof.

# 6. Create Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "db_modified": $DB_MODIFIED,
    "db_verification": $DB_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="