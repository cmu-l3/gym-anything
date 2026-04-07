#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Expected screenshot path
EXPECTED_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/noise_floor_config.png"

# Check if the specific screenshot file exists and was created during the task
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Take final system state screenshot (fallback if agent didn't take one, or to verify session state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid_time": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "agent_screenshot_path": "$EXPECTED_PATH",
    "app_was_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy the agent's screenshot to /tmp for easier extraction by verifier if needed
if [ "$SCREENSHOT_EXISTS" == "true" ]; then
    cp "$EXPECTED_PATH" /tmp/agent_screenshot_evidence.png 2>/dev/null || true
    chmod 666 /tmp/agent_screenshot_evidence.png 2>/dev/null || true
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="