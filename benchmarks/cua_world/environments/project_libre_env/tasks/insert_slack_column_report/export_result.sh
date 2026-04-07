#!/bin/bash
echo "=== Exporting insert_slack_column_report results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Projects/critical_path_report.txt"

# Check report file status
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Check if app is still running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for export (copy to /tmp so verifier can access them easily)
# The framework copies from the container's /tmp usually, or we can point to the path.
# We will create a JSON result and also copy the text report to a temp location 
# that is definitely accessible.
cp "$REPORT_PATH" /tmp/exported_report.txt 2>/dev/null || true
chmod 644 /tmp/exported_report.txt 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "app_was_running": $APP_RUNNING,
    "report_file_path": "/tmp/exported_report.txt"
}
EOF

# Move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"