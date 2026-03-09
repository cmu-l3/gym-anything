#!/bin/bash
echo "=== Exporting Document Type Hierarchy Result ==="

source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_DIR="/home/ga/eclipse-workspace/MessageSystem"
OUTPUT_FILE="$PROJECT_DIR/handler_audit.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if file exists and gather stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Read content (base64 encoded to handle newlines safely in JSON)
    FILE_CONTENT=$(base64 -w 0 "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Eclipse is still running
APP_RUNNING=$(pgrep -f "eclipse" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIME,
    "task_end": $TASK_END_TIME,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "file_content_b64": "$FILE_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Save result safely
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="