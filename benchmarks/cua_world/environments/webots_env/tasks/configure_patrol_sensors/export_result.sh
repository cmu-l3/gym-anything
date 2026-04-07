#!/bin/bash
# Export script for configure_patrol_sensors task

echo "=== Exporting configure_patrol_sensors result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Desktop/patrol_robot_configured.wbt"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write summary JSON for the verifier
# The actual heavy-lifting of parsing the .wbt file is done in verifier.py
# using the copy_from_env mechanism to ensure robust regex processing.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "task_start_timestamp": $TASK_START_TIME,
    "export_timestamp": $(date +%s),
    "output_path": "$OUTPUT_FILE"
}
EOF

# Make sure it's readable
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="