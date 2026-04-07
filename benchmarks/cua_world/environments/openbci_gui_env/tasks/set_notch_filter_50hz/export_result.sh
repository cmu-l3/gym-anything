#!/bin/bash
echo "=== Exporting set_notch_filter_50hz result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if OpenBCI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check for user-generated screenshot
USER_SCREENSHOT_PATH="/tmp/notch_filter_result.png"
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$USER_SCREENSHOT_PATH" ]; then
    USER_SCREENSHOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$USER_SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        USER_SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture final state screenshot (system enforced)
take_screenshot /tmp/task_final.png
FINAL_SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    FINAL_SCREENSHOT_EXISTS="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_valid_time": $USER_SCREENSHOT_CREATED_DURING_TASK,
    "final_screenshot_path": "/tmp/task_final.png",
    "user_screenshot_path": "$USER_SCREENSHOT_PATH"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="