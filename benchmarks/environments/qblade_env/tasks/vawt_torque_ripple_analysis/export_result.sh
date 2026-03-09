#!/bin/bash
echo "=== Exporting VAWT Torque Ripple Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/vawt_ripple.wpa"
REPORT_PATH="/home/ga/Documents/projects/ripple_report.txt"

# Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Search for any exported simulation data files (txt or csv or dat)
# Look for files created during the task in Documents
EXPORTED_DATA_FILES=$(find /home/ga/Documents -type f \( -name "*.txt" -o -name "*.csv" -o -name "*.dat" \) -newermt "@$TASK_START" ! -name "ripple_report.txt" 2>/dev/null)
DATA_EXPORT_FOUND="false"
if [ -n "$EXPORTED_DATA_FILES" ]; then
    DATA_EXPORT_FOUND="true"
    # Capture the first few lines of the largest exported file to verify it looks like simulation data
    LARGEST_DATA_FILE=$(ls -S $EXPORTED_DATA_FILES | head -1)
    DATA_FILE_PREVIEW=$(head -n 5 "$LARGEST_DATA_FILE" | base64 -w 0)
fi

# Check if QBlade is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content_base64": "$REPORT_CONTENT",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "data_export_found": $DATA_EXPORT_FOUND,
    "data_file_preview_base64": "${DATA_FILE_PREVIEW:-}",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="