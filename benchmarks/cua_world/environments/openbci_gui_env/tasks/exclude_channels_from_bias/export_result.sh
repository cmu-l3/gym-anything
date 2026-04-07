#!/bin/bash
echo "=== Exporting exclude_channels_from_bias results ==="

# Source utilities for screenshot function
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot requested exists and was created during task
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/bias_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
    
    # Get file size
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
else
    SCREENSHOT_SIZE="0"
fi

# 2. Check if Application is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture Final State (System Screenshot)
# This is distinct from the user's proof screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_valid_time": $SCREENSHOT_VALID,
    "user_screenshot_size": $SCREENSHOT_SIZE,
    "user_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_system_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="