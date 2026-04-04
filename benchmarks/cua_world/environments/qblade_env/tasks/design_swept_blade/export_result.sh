#!/bin/bash
echo "=== Exporting design_swept_blade result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_FILE="/home/ga/Documents/projects/swept_blade.wpa"
STL_FILE="/home/ga/Documents/projects/swept_blade.stl"

# Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_MTIME=0
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_FILE" 2>/dev/null || echo "0")
fi

# Check STL File
STL_EXISTS="false"
STL_SIZE=0
if [ -f "$STL_FILE" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c%s "$STL_FILE" 2>/dev/null || echo "0")
fi

# Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)

# Check for file modification during task
FILE_CREATED_DURING_TASK="false"
if [ "$PROJECT_EXISTS" = "true" ] && [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$PROJECT_FILE",
    "project_size": $PROJECT_SIZE,
    "stl_exists": $STL_EXISTS,
    "stl_size": $STL_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"