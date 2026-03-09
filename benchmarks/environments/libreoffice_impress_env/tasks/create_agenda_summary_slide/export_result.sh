#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Agenda Summary Slide Result ==="

TARGET_FILE="/home/ga/Documents/Presentations/strategic_initiatives.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Attempt to save the presentation (Ctrl+S)
echo "Attempting to save presentation..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 3
fi

# 2. Check if file was modified
FILE_MODIFIED="false"
if [ -f "$TARGET_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
        echo "✅ File was modified during task"
    else
        echo "⚠️ File was NOT modified during task"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
else
    FILE_SIZE="0"
    echo "❌ Target file not found"
fi

# 3. Check if Impress is still running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "target_file": "$TARGET_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="