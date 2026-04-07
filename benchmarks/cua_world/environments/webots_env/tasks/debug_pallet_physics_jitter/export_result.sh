#!/bin/bash
echo "=== Exporting debug_pallet_physics_jitter result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Desktop/stabilized_pallet.wbt"
FILE_EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if the file was created/modified during the task
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON using a temp file for permission safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="