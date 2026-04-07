#!/bin/bash
# Export script for configure_sar_tracked_vehicle task
# Gathers metadata about the saved world file.

echo "=== Exporting configure_sar_tracked_vehicle result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/sar_robot_configured.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_SAVED_AFTER_START="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    
    # Check if file was actually saved during the task
    TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_SAVED_AFTER_START="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
    echo "Saved after start: $FILE_SAVED_AFTER_START"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON. (Detailed values are extracted programmatically in verifier.py)
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "saved_after_start": $FILE_SAVED_AFTER_START,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="