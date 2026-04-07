#!/bin/bash
set -e

echo "=== Exporting Hotel Revenue Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "onlyoffice|DesktopEditors" > /dev/null && echo "true" || echo "false")

# Try to trigger a save if it's still open
if [ "$APP_RUNNING" = "true" ]; then
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 2
    pkill -f "onlyoffice|DesktopEditors" 2>/dev/null || true
    sleep 2
fi

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/hotel_revenue_analysis.xlsx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Export metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export Complete. Results saved."
cat /tmp/task_result.json