#!/bin/bash
# export_result.sh for generate_maven_client_config
set -e
echo "=== Exporting generate_maven_client_config result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/maven_settings.xml"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Anti-gaming: Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi

    # Read content for verification (safe read)
    # limit size to prevent issues if agent dumps huge file
    FILE_CONTENT=$(head -c 10000 "$OUTPUT_FILE" | base64 -w 0)
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
    FILE_CONTENT=""
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_base64": "$FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"