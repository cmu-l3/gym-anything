#!/bin/bash
echo "=== Exporting export_html_logbook task results ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

TARGET_DIR="/home/ga/Documents/WebLog"
TARGET_FILE="$TARGET_DIR/divelog.html"

DIR_EXISTS="false"
if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
fi

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES="0"
CONTAINS_HTML_TAG="false"
CONTAINS_DIVE_DATA="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check for basic HTML signatures
    if grep -qi "<html" "$TARGET_FILE" 2>/dev/null; then
        CONTAINS_HTML_TAG="true"
    fi
    
    # Check for actual dive data expected from SampleDivesV2.ssrf
    # "Sund Rock" is a known dive site in this logbook
    if grep -qi "Sund Rock" "$TARGET_FILE" 2>/dev/null; then
        CONTAINS_DIVE_DATA="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "dir_exists": $DIR_EXISTS,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "contains_html_tag": $CONTAINS_HTML_TAG,
    "contains_dive_data": $CONTAINS_DIVE_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="