#!/bin/bash
echo "=== Exporting Configure Accelerometer Layout Result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot requested exists
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/accel_layout.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if OpenBCI GUI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture the final screen state (independent of agent's screenshot)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "user_screenshot_size": $SCREENSHOT_SIZE,
    "user_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_state_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# If the user took a screenshot, copy it to /tmp for easy retrieval by verifier
if [ "$SCREENSHOT_EXISTS" = "true" ]; then
    cp "$EXPECTED_SCREENSHOT" /tmp/user_accel_screenshot.png
    chmod 666 /tmp/user_accel_screenshot.png
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="