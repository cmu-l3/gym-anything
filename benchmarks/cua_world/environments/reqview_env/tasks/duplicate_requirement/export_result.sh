#!/bin/bash
echo "=== Exporting duplicate_requirement results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_PATH=$(cat /tmp/task_project_path.txt 2>/dev/null)
INITIAL_COUNT=$(cat /tmp/initial_req_count.txt 2>/dev/null || echo "0")

# Default values
SRS_MODIFIED="false"
SRS_MTIME="0"
SRS_SIZE="0"
APP_RUNNING="false"

# Check if ReqView is running
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Check SRS file status
SRS_FILE="$PROJECT_PATH/documents/SRS.json"
if [ -f "$SRS_FILE" ]; then
    SRS_SIZE=$(stat -c %s "$SRS_FILE" 2>/dev/null || echo "0")
    SRS_MTIME=$(stat -c %Y "$SRS_FILE" 2>/dev/null || echo "0")
    
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_req_count": $INITIAL_COUNT,
    "project_path": "$PROJECT_PATH",
    "srs_file_exists": $([ -f "$SRS_FILE" ] && echo "true" || echo "false"),
    "srs_modified_during_task": $SRS_MODIFIED,
    "srs_mtime": $SRS_MTIME,
    "srs_size_bytes": $SRS_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="