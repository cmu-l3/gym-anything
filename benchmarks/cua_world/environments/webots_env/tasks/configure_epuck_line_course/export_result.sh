#!/bin/bash
# Export script for configure_epuck_line_course task
# Checks if the agent saved the configured world and extracts its state

echo "=== Exporting configure_epuck_line_course result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/epuck_line_follow.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
    echo "Created during task: $FILE_CREATED_DURING_TASK"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/configure_epuck_line_course_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/configure_epuck_line_course_result.json"
cat /tmp/configure_epuck_line_course_result.json

echo "=== Export Complete ==="