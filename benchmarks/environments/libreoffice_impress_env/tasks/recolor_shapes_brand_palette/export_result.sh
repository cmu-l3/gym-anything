#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Recolor Shapes Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Attempt to save the file (Ctrl+S) in case the agent forgot
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    safe_xdotool ga :1 key ctrl+s
    sleep 2
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

FILE_PATH="/home/ga/Documents/Presentations/esg_report.odp"

# Check file stats
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    FILE_HASH=$(md5sum "$FILE_PATH" | awk '{print $1}')
    
    # Check modification
    INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "none")
    if [ "$FILE_HASH" != "$INITIAL_HASH" ] && [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_HASH=""
    FILE_MODIFIED="false"
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="