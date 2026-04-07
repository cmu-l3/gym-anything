#!/bin/bash
echo "=== Exporting Configure Pulse Widget Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected output path
SCREENSHOT_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/pulse_config.png"

# Check if screenshot exists and was created during task
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Check if OpenBCI GUI is still running (it should be)
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Take a system-level final screenshot (in case the agent didn't take one, or for VLM verification)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final_system.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "$SCREENSHOT_PATH",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "app_was_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final_system.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="