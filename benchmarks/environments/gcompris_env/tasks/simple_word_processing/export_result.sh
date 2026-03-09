#!/bin/bash
echo "=== Exporting Simple Word Processing Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot (system level)
take_screenshot /tmp/task_final.png

# Check if the expected output file exists
OUTPUT_PATH="/home/ga/Documents/field_trip_notice.png"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$OUTPUT_PATH"
}
EOF

# Move result to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"