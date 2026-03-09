#!/bin/bash
# Export script for Create Appointment Status task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get the initial count recorded during setup
INITIAL_COUNT=$(cat /tmp/initial_status_count 2>/dev/null || echo "0")

# 3. Query current state of appointment_status table
# We look specifically for the requested status 'V'
echo "Querying database for status 'V'..."
STATUS_RECORD=$(oscar_query "SELECT status, description, color FROM appointment_status WHERE status='V' LIMIT 1" 2>/dev/null)

# 4. Get total count
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment_status" 2>/dev/null || echo "0")

# 5. Parse the record if found
FOUND="false"
REC_STATUS=""
REC_DESC=""
REC_COLOR=""

if [ -n "$STATUS_RECORD" ]; then
    FOUND="true"
    # Parse tab-separated output
    REC_STATUS=$(echo "$STATUS_RECORD" | cut -f1)
    REC_DESC=$(echo "$STATUS_RECORD" | cut -f2)
    REC_COLOR=$(echo "$STATUS_RECORD" | cut -f3)
    echo "Found record: Status='$REC_STATUS', Desc='$REC_DESC', Color='$REC_COLOR'"
else
    echo "Status 'V' not found in database."
fi

# 6. Verify navigation (simple check if Firefox is still running)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 7. Create JSON result
# Using a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": $FOUND,
    "record": {
        "status": "$REC_STATUS",
        "description": "$REC_DESC",
        "color": "$REC_COLOR"
    },
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="