#!/bin/bash
set -euo pipefail

echo "=== Exporting cooperative testworld task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Desktop/cooperative_push.wbt"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
APP_WAS_RUNNING="false"

# Check if Webots was running
if pgrep -f "webots" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# Check if the required file exists and was created during the task
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_PATH ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_PATH"
fi

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_WAS_RUNNING,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="