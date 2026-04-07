#!/bin/bash
set -euo pipefail

echo "=== Exporting Space Debris Conjunction Assessment Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Save document cleanly using OnlyOffice shortcuts if running
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    echo "Sending Save command to ONLYOFFICE..."
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
    sleep 3
    
    # Send Quit command
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
    sleep 1
fi

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/conjunction_assessment.xlsx"

FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found output file: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "WARNING: Target file not found at $OUTPUT_PATH"
fi

APP_RUNNING="false"
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    APP_RUNNING="true"
fi

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

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="