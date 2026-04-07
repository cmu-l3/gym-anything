#!/bin/bash
echo "=== Exporting create_wbs_summary_group results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file details
OUTPUT_PATH="/home/ga/Projects/updated_project.xml"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Check if app is still running
APP_RUNNING="false"
if pgrep -f "projectlibre" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# Using a temp file and moving it ensures atomic write/permission safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_path": "$OUTPUT_PATH",
    "output_exists": $FILE_EXISTS,
    "output_size": $FILE_SIZE,
    "file_created_during_task": $FILE_MODIFIED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json