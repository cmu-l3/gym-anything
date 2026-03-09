#!/bin/bash
echo "=== Exporting Create Work Log Type results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the specific work log type
# We select relevant columns to verify correctness
# Note: Table names in SDP are usually lowercase in Postgres
DB_RESULT=$(sdp_db_exec "SELECT name, description, rate, createdtime FROM worklogtype WHERE name = 'On-Site Repair';" 2>/dev/null)

# Check if we got a result
RECORD_FOUND="false"
NAME=""
DESC=""
RATE=""
CREATED_TIME=""

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    # Parse pipe-delimited result from sdp_db_exec (psql -A -t)
    # Format typically: name|description|rate|createdtime
    IFS='|' read -r NAME DESC RATE CREATED_TIME <<< "$DB_RESULT"
fi

# Get final count
FINAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM worklogtype;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_wlt_count.txt 2>/dev/null || echo "0")

# Check if application (Firefox) is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_found": $RECORD_FOUND,
    "name": "$(echo $NAME | sed 's/"/\\"/g')",
    "description": "$(echo $DESC | sed 's/"/\\"/g')",
    "rate": "$(echo $RATE | sed 's/"/\\"/g')",
    "db_created_time": "$(echo $CREATED_TIME | sed 's/"/\\"/g')",
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="