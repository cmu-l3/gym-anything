#!/bin/bash
echo "=== Exporting isolate_motor_channels_screenshot results ==="

# 1. Record end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final system screenshot (evidence of state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check for App-Generated Screenshot
# OpenBCI saves screenshots to ~/Documents/OpenBCI_GUI/Screenshots/
# Format is typically "OpenBCI-GUI-v5.2.2-2023-10-27_10-00-00.png"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"
FOUND_SCREENSHOT="false"
SCREENSHOT_PATH=""
SCREENSHOT_SIZE="0"

# Find the most recent PNG file in the directory (ignoring the backup folder)
LATEST_FILE=$(find "$SCREENSHOTS_DIR" -maxdepth 1 -name "*.png" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$LATEST_FILE")
    
    # Check if created AFTER task start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FOUND_SCREENSHOT="true"
        SCREENSHOT_PATH="$LATEST_FILE"
        SCREENSHOT_SIZE=$(stat -c %s "$LATEST_FILE")
        echo "Found valid app screenshot: $LATEST_FILE"
        
        # Copy to /tmp for verification access
        cp "$LATEST_FILE" /tmp/app_generated_screenshot.png
        chmod 644 /tmp/app_generated_screenshot.png
    else
        echo "Found screenshot, but it's too old (created before task)."
    fi
else
    echo "No screenshot file found in $SCREENSHOTS_DIR"
fi

# 4. Check if App is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_screenshot_created": $FOUND_SCREENSHOT,
    "app_screenshot_path": "$SCREENSHOT_PATH",
    "app_screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "final_system_screenshot": "/tmp/task_final.png",
    "app_screenshot_copy": "/tmp/app_generated_screenshot.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json