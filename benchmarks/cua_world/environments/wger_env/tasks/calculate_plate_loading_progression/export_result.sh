#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_WEIGHT=$(cat /tmp/squat_base_weight.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/next_squat_plates.txt"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

# Evaluate output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read file: extract only numbers/decimals, convert newlines to commas for JSON safety
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | grep -o '[0-9.]*' | tr '\n' ',' | sed 's/,$//')
fi

# Package JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "base_weight": $BASE_WEIGHT,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT"
}
EOF

# Move payload to a location the verifier can safely access via copy_from_env
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="