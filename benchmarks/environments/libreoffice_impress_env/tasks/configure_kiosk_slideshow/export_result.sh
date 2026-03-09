#!/bin/bash
echo "=== Exporting Configure Kiosk Slideshow Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

TARGET_FILE="/home/ga/Documents/Presentations/community_kiosk.odp"

# Check if file exists and gather stats
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    
    # Check modification status
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_TIME="true"
    else
        FILE_MODIFIED_TIME="false"
    fi
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED_HASH="true"
    else
        FILE_MODIFIED_HASH="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MODIFIED_TIME="false"
    FILE_MODIFIED_HASH="false"
fi

# Check if Impress is still running (it's okay if it is or isn't, just for info)
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_time": $FILE_MODIFIED_TIME,
    "file_modified_hash": $FILE_MODIFIED_HASH,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="