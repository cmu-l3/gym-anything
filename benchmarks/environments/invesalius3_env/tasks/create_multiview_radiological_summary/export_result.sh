#!/bin/bash
echo "=== Exporting create_multiview_radiological_summary result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/radiology_summary.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final system screenshot (backup evidence)
take_screenshot /tmp/task_end.png

# Check output file status
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="