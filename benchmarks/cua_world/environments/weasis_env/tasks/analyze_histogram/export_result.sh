#!/bin/bash
echo "=== Exporting analyze_histogram task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE checking files
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/DICOM/exports/histogram_report.txt"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT='""'

# Check if report file exists and was created after task start
if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Safely extract file content to JSON (up to 50 lines to prevent buffer bloat)
    FILE_CONTENT=$(cat "$REPORT_PATH" | head -n 50 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
fi

APP_RUNNING=$(pgrep -f weasis > /dev/null && echo "true" || echo "false")

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": $FILE_CONTENT,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
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