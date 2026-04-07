#!/bin/bash
echo "=== Exporting configure_exoskeleton_ankle_biomechanics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/exoskeleton_biomechanics.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time against start time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
    echo "Modified during task: $FILE_MODIFIED_DURING_TASK"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/exoskeleton_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)",
    "task_start": $TASK_START
}
EOF

echo "Result JSON written to /tmp/exoskeleton_result.json"
cat /tmp/exoskeleton_result.json

echo "=== Export Complete ==="