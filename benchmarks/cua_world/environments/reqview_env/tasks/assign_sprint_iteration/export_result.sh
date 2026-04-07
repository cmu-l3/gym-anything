#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_PATH=$(find /home/ga/Documents/ReqView -name "sprint_planning_project" -type d | head -1)
SRS_PATH="$PROJECT_PATH/documents/SRS.json"

# Check SRS file modification
FILE_MODIFIED_DURING_TASK="false"
SRS_SIZE="0"
if [ -f "$SRS_PATH" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_PATH" 2>/dev/null || echo "0")
    SRS_SIZE=$(stat -c %s "$SRS_PATH" 2>/dev/null || echo "0")
    
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_file_path": "$SRS_PATH",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size_bytes": $SRS_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to reliable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="