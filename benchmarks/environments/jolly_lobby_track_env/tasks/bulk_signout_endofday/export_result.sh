#!/bin/bash
echo "=== Exporting Bulk Sign-out Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Agent's Confirmation Screenshot
EXPECTED_SCREENSHOT="/tmp/signout_complete.png"
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Check if it was created during the task
    SCREENSHOT_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT")
    if [ "$SCREENSHOT_TIME" -gt "$TASK_START" ]; then
        SCREENSHOT_VALID_TIME="true"
    else
        SCREENSHOT_VALID_TIME="false"
    fi
else
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_VALID_TIME="false"
fi

# 2. Capture Final System State Screenshot (Truth)
FINAL_SCREENSHOT="/tmp/task_final_state.png"
DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || DISPLAY=:1 import -window root "$FINAL_SCREENSHOT" 2>/dev/null || true

# 3. Check if Lobby Track is still running
if pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid_time": $SCREENSHOT_VALID_TIME,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_system_screenshot_path": "$FINAL_SCREENSHOT",
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="