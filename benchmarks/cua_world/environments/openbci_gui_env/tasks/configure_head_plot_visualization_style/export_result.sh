#!/bin/bash
echo "=== Exporting Configure Head Plot Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot file exists
EXPECTED_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_viridis.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if OpenBCI is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 3. Take final system screenshot (what the screen looks like right now)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="