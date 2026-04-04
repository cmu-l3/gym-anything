#!/bin/bash
echo "=== Exporting Record Patient Amendment Result ==="

source /workspace/scripts/task_utils.sh

# Get Task Metadata
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_amendment_count 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 2. Query Database for Results
echo "Querying amendments for PID: $PID..."

# Get current count
FINAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM amendments WHERE pid='$PID'" 2>/dev/null || echo "0")

# Calculate count difference
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# Get the most recent amendment for this patient
# We fetch specific fields: amendment_date, amendment_status, amendment_desc
# Note: Field names based on standard OpenEMR/LibreHealth schema. 
# If exact schema varies, we select * and parse in python, but specific columns are safer if known.
# Common columns: id, pid, amendment_date, amendment_status, amendment_desc, created_time
LATEST_RECORD=$(librehealth_query "SELECT amendment_date, amendment_status, amendment_desc FROM amendments WHERE pid='$PID' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# Parse the tab-separated result
# MySQL -N output is tab separated
REC_DATE=$(echo "$LATEST_RECORD" | awk -F'\t' '{print $1}')
REC_STATUS=$(echo "$LATEST_RECORD" | awk -F'\t' '{print $2}')
REC_DESC=$(echo "$LATEST_RECORD" | awk -F'\t' '{print $3}')

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_pid": $PID,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_diff": $COUNT_DIFF,
    "record_found": $([ -n "$LATEST_RECORD" ] && echo "true" || echo "false"),
    "record_date": "$REC_DATE",
    "record_status": "$REC_STATUS",
    "record_desc": $(echo "$REC_DESC" | jq -R .),
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="