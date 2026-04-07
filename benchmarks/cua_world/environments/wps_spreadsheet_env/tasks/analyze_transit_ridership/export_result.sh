#!/bin/bash
set -euo pipefail

echo "=== Exporting analyze_transit_ridership task result ==="

export DISPLAY=${DISPLAY:-:1}
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DATA_FILE="/home/ga/Documents/cta_ridership_oct2023.xlsx"

# Take final screenshot for VLM and manual review
echo "Taking final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$DATA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DATA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$DATA_FILE" 2>/dev/null || echo "0")
    
    # Check if file was modified after the task started
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

APP_RUNNING="false"
if pgrep -x "et" > /dev/null || pgrep -f "/office6/et" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="