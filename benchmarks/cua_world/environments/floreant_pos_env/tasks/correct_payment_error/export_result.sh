#!/bin/bash
echo "=== Exporting correct_payment_error results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if app was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Stop Floreant POS to release the Derby database lock
# CRITICAL: Embedded Derby cannot be queried while the app is running
echo "Stopping Floreant POS to query database..."
kill_floreant

# 4. Locate Derby JARs for tools
DERBY_LIB_DIR="/opt/floreantpos/lib"
DERBY_TOOLS_JAR=$(find "$DERBY_LIB_DIR" -name "derbytools*.jar" | head -1)
DERBY_JAR=$(find "$DERBY_LIB_DIR" -name "derby*.jar" | grep -v "tools" | head -1)

if [ -z "$DERBY_TOOLS_JAR" ] || [ -z "$DERBY_JAR" ]; then
    echo "ERROR: Derby JARs not found in $DERBY_LIB_DIR"
    # Fallback to system if available, though unlikely in this container
    DERBY_CLASSPATH="/usr/share/java/derby.jar:/usr/share/java/derbytools.jar"
else
    DERBY_CLASSPATH="$DERBY_JAR:$DERBY_TOOLS_JAR"
fi

# 5. Locate the Database
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" | xargs dirname)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/opt/floreantpos/database/derby-server"
fi

echo "Using Database: $DB_PATH"
echo "Classpath: $DERBY_CLASSPATH"

# 6. Query the database for tickets and transactions created during the task
# We construct a SQL script to dump relevant tables
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert unix timestamp to simple approximation if needed, but easier to just dump all 
# recent transactions and filter in python.
# Note: Floreant TICKET table usually has CREATE_DATE or ID.

SQL_SCRIPT="/tmp/query_transactions.sql"
cat > "$SQL_SCRIPT" << EOF
CONNECT 'jdbc:derby:$DB_PATH';

-- Dump recent tickets (assuming auto-increment ID, we just take the last 10)
SELECT t.ID, t.CREATE_DATE, t.CLOSED, t.VOIDED, t.TOTAL_AMOUNT, t.PAID_AMOUNT 
FROM TICKET t 
ORDER BY t.ID DESC 
FETCH FIRST 10 ROWS ONLY;

-- Dump recent transactions linked to tickets
-- Joining might be complex if we don't know exact schema version, 
-- so we dump transactions separately.
SELECT tr.ID, tr.TICKET_ID, tr.TRANSACTION_TYPE, tr.TENDER_TYPE, tr.AMOUNT, tr.TRANSACTION_TIME
FROM TRANSACTIONS tr
ORDER BY tr.ID DESC
FETCH FIRST 20 ROWS ONLY;

DISCONNECT;
EXIT;
EOF

# Run the query using ij tool
JAVA_CMD="java -cp $DERBY_CLASSPATH -Dderby.system.home=/opt/floreantpos/database org.apache.derby.tools.ij"
OUTPUT_FILE="/tmp/db_dump.txt"

echo "Running DB query..."
$JAVA_CMD "$SQL_SCRIPT" > "$OUTPUT_FILE" 2>&1

echo "DB Query Output (First 20 lines):"
head -n 20 "$OUTPUT_FILE"

# 7. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "app_was_running": $APP_RUNNING,
    "db_dump_path": "$OUTPUT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="