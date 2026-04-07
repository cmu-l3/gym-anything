#!/bin/bash
echo "=== Exporting create_saved_traceability_view results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured"

# Check if SRS.json exists and when it was modified
# This is used for anti-gaming (did the file actually change?)
PROJECT_DIR="/home/ga/Documents/ReqView/rtm_view_task_project"
SRS_FILE="$PROJECT_DIR/documents/SRS.json"

FILE_MODIFIED="false"
if [ -f "$SRS_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$SRS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "project_path": "$PROJECT_DIR",
    "srs_path": "$SRS_FILE"
}
EOF

echo "Result JSON created:"
cat /tmp/task_result.json

echo "=== Export complete ==="