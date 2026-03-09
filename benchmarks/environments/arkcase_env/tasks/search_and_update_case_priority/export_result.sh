#!/bin/bash
# post_task: Export results for verification

echo "=== Exporting search_and_update_case_priority results ==="

source /workspace/scripts/task_utils.sh

# 1. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
INITIAL_PRIORITY=$(cat /tmp/initial_priority.txt 2>/dev/null || echo "Unknown")

echo "Checking Case ID: $TARGET_ID"

# 2. Query API for Current State
# We need to fetch the case to see if priority changed
API_DATA="{}"
CURRENT_PRIORITY="Unknown"
CURRENT_TITLE="Unknown"
LAST_MODIFIED="0"

if [ -n "$TARGET_ID" ]; then
    RESPONSE=$(arkcase_api GET "plugin/complaint/${TARGET_ID}" "" 2>/dev/null)
    
    # Save full response for debug
    echo "$RESPONSE" > /tmp/api_response_debug.json
    
    # Parse relevant fields
    CURRENT_PRIORITY=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('priority', 'Unknown'))" 2>/dev/null || echo "Error")
    CURRENT_TITLE=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintTitle', 'Unknown'))" 2>/dev/null || echo "Error")
fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "target_case_id": "$TARGET_ID",
    "initial_priority": "$INITIAL_PRIORITY",
    "current_priority": "$CURRENT_PRIORITY",
    "current_title": "$(echo "$CURRENT_TITLE" | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="