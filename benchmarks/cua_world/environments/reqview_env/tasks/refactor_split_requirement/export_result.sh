#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define path to the SRS document we expect to be modified
PROJECT_DIR="/home/ga/Documents/ReqView/refactor_split_req_project"
SRS_JSON="$PROJECT_DIR/documents/SRS.json"

# Check file modification
FILE_MODIFIED="false"
FILE_SIZE="0"
if [ -f "$SRS_JSON" ]; then
    FILE_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    FILE_SIZE=$(stat -c %s "$SRS_JSON" 2>/dev/null || echo "0")
fi

# Check if app running
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_file_path": "$SRS_JSON",
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="