#!/bin/bash
# Export script for configure_vacuum_gripper task

echo "=== Exporting configure_vacuum_gripper result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/palletizer_gripper.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON (using temp file to avoid permission issues)
TEMP_JSON=$(mktemp /tmp/configure_vacuum_gripper_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/configure_vacuum_gripper_result.json 2>/dev/null || sudo rm -f /tmp/configure_vacuum_gripper_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_vacuum_gripper_result.json
chmod 666 /tmp/configure_vacuum_gripper_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/configure_vacuum_gripper_result.json"
cat /tmp/configure_vacuum_gripper_result.json

echo "=== Export Complete ==="