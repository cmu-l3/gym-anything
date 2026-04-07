#!/bin/bash
# Export script for configure_demo_presentation task
# Checks if the agent saved the configured world and exports metadata for the verifier.

echo "=== Exporting configure_demo_presentation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/demo_configured.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
    
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        echo "File was correctly created/modified during the task window."
    else
        echo "WARNING: File timestamp is older than task start time!"
    fi
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/configure_demo_presentation_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/configure_demo_presentation_result.json"
cat /tmp/configure_demo_presentation_result.json

echo "=== Export Complete ==="