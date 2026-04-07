#!/bin/bash
echo "=== Exporting trace_reqs_by_content results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Project paths
PROJECT_PATH="/home/ga/Documents/ReqView/trace_content_project"
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

# Check if SRS was modified
SRS_MODIFIED="false"
if [ -f "$SRS_JSON" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# Check if ReqView is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_modified": $SRS_MODIFIED,
    "app_running": $APP_RUNNING,
    "project_path": "$PROJECT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="