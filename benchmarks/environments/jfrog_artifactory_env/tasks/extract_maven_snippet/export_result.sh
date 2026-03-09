#!/bin/bash
echo "=== Exporting extract_maven_snippet results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Desktop/maven_snippet.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CONTENT_BASE64=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (encode to base64 to avoid JSON breaking chars)
    CONTENT_BASE64=$(base64 -w 0 "$OUTPUT_PATH")
fi

# Check if Artifactory is still running
APP_RUNNING="false"
if pgrep -f "artifactory" > /dev/null || docker ps | grep -q artifactory; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "content_base64": "$CONTENT_BASE64",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="