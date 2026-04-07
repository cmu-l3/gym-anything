#!/bin/bash
set -e

echo "=== Exporting fillet_arc_profile result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check output file
TARGET_FILE="/home/ga/Documents/SolveSpace/fillet_profile.slvs"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f "solvespace" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final_state.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Safely copy to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="