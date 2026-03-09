#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_user_type task results ==="

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Stop Floreant POS
# CRITICAL: We MUST stop the application to release the lock on the embedded Derby database
# so we can query it for verification.
kill_floreant
sleep 3

# 3. Prepare for Database Query
DB_PATH=$(cat /tmp/derby_db_path.txt 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    # Fallback search
    DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
fi

# Locate Derby JARs
DERBY_CP=$(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null | tr '\n' ':')
if [ -z "$DERBY_CP" ]; then
    DERBY_CP=$(find /opt/floreantpos -name "derby*.jar" 2>/dev/null | tr '\n' ':')
fi

# 4. Query the Database
# We check if a User Type with the name "Shift Supervisor" exists
cat > /tmp/verify_query.sql << SQLEOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT ID, NAME FROM USER_TYPE WHERE UPPER(NAME) = 'SHIFT SUPERVISOR';
DISCONNECT;
EXIT;
SQLEOF

echo "Running DB Verification Query..."
QUERY_OUTPUT=$(java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/verify_query.sql 2>/dev/null || echo "QUERY_FAILED")

echo "Query Output:"
echo "$QUERY_OUTPUT"

# Parse Result
# Typical output contains the row if found, e.g.:
# ID         |NAME
# -----------------------------------
# 123        |Shift Supervisor
RECORD_FOUND="false"
if echo "$QUERY_OUTPUT" | grep -qi "Shift Supervisor"; then
    RECORD_FOUND="true"
fi

# 5. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_MTIME=$(stat -c %Y "$DB_PATH/seg0" 2>/dev/null || echo "0")

DB_MODIFIED="false"
if [ "$DB_MTIME" -gt "$TASK_START" ]; then
    DB_MODIFIED="true"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "record_found": $RECORD_FOUND,
    "db_modified_during_task": $DB_MODIFIED,
    "task_start": $TASK_START,
    "db_mtime": $DB_MTIME,
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