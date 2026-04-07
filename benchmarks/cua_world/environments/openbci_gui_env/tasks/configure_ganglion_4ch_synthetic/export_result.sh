#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check User Screenshot (The one requested in description)
SCREENSHOT_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/ganglion_4ch_display.png"
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_VALID="false"
USER_SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    USER_SCREENSHOT_EXISTS="true"
    USER_SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp (Anti-gaming)
    FILE_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        USER_SCREENSHOT_VALID="true"
    fi
fi

# 2. Check if Application is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 3. Capture Final System Screenshot (For VLM verification of state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_valid_timestamp": $USER_SCREENSHOT_VALID,
    "user_screenshot_size": $USER_SCREENSHOT_SIZE,
    "user_screenshot_path": "$SCREENSHOT_PATH",
    "app_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Export complete. JSON result:"
cat /tmp/task_result.json