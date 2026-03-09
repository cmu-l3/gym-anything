#!/bin/bash
# Export script for Create Tickler Reminder task
# Extracts database state to JSON for verification

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Read setup data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MARIA_DEMO_NO=$(cat /tmp/maria_demo_no.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_tickler_count.txt 2>/dev/null || echo "0")

# ============================================================
# Query Database for Result
# ============================================================

# We look for the most recent tickler for this patient
# We fetch relevant columns: tickler_no, message, status, priority, service_date, task_assigned_to, update_date
TICKLER_DATA=$(oscar_query "
SELECT 
    tickler_no, 
    message, 
    status, 
    priority, 
    service_date, 
    task_assigned_to, 
    update_date 
FROM tickler 
WHERE demographic_no='$MARIA_DEMO_NO' 
ORDER BY tickler_no DESC 
LIMIT 1" 2>/dev/null)

# Get current count
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='$MARIA_DEMO_NO'" 2>/dev/null || echo "0")

# Check if application (Firefox) is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Parse SQL result into variables for JSON construction
# Note: SQL result is tab-separated
T_ID=""
T_MSG=""
T_STATUS=""
T_PRIORITY=""
T_DATE=""
T_ASSIGNED=""
T_UPDATE=""

if [ -n "$TICKLER_DATA" ]; then
    T_ID=$(echo "$TICKLER_DATA" | cut -f1)
    T_MSG=$(echo "$TICKLER_DATA" | cut -f2)
    T_STATUS=$(echo "$TICKLER_DATA" | cut -f3)
    T_PRIORITY=$(echo "$TICKLER_DATA" | cut -f4)
    T_DATE=$(echo "$TICKLER_DATA" | cut -f5)
    T_ASSIGNED=$(echo "$TICKLER_DATA" | cut -f6)
    T_UPDATE=$(echo "$TICKLER_DATA" | cut -f7)
fi

# Convert timestamps to unix for comparison
T_UPDATE_TS=0
if [ -n "$T_UPDATE" ]; then
    T_UPDATE_TS=$(date -d "$T_UPDATE" +%s 2>/dev/null || echo "0")
fi

# Sanitize message for JSON (escape quotes)
T_MSG_JSON=$(echo "$T_MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "app_running": $APP_RUNNING,
    "tickler": {
        "found": $([ -n "$T_ID" ] && echo "true" || echo "false"),
        "id": "$T_ID",
        "message": $T_MSG_JSON,
        "status": "$T_STATUS",
        "priority": "$T_PRIORITY",
        "service_date": "$T_DATE",
        "assigned_to": "$T_ASSIGNED",
        "update_ts": $T_UPDATE_TS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="