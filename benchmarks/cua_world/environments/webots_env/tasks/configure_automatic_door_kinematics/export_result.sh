#!/bin/bash
# Export script for configure_automatic_door_kinematics task

echo "=== Exporting configure_automatic_door_kinematics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/hospital_door_fixed.wbt"

FILE_EXISTS="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    FILE_CREATED_DURING_TASK="false"
fi

# Write result JSON
cat > /tmp/configure_door_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/configure_door_result.json"
cat /tmp/configure_door_result.json

echo "=== Export Complete ==="