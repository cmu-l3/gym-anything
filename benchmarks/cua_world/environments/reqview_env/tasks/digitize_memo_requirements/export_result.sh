#!/bin/bash
echo "=== Exporting digitize_memo_requirements results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_srs_mtime.txt 2>/dev/null || echo "0")

SRS_PATH="/home/ga/Documents/ReqView/digitize_memo_project/documents/SRS.json"

# Check if SRS file exists and was modified
SRS_EXISTS="false"
SRS_MODIFIED="false"
SRS_SIZE="0"

if [ -f "$SRS_PATH" ]; then
    SRS_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$SRS_PATH" 2>/dev/null || echo "0")
    SRS_SIZE=$(stat -c %s "$SRS_PATH" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_exists": $SRS_EXISTS,
    "srs_modified_during_task": $SRS_MODIFIED,
    "srs_size_bytes": $SRS_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="