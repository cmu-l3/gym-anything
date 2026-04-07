#!/bin/bash
echo "=== Exporting fix_broken_traceability_links result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Project file path
PROJECT_FILE="/home/ga/Documents/ReqView/fix_broken_links_project/documents/SRS.json"

# Check if file was modified
FILE_MODIFIED="false"
FILE_SIZE="0"
if [ -f "$PROJECT_FILE" ]; then
    FILE_SIZE=$(stat -c %s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="