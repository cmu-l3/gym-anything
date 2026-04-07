#!/bin/bash
echo "=== Exporting configure_ncap_pedestrian_aeb result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/ncap_aeb_configured.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON metadata
cat > /tmp/ncap_aeb_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "file_created_during_task": $CREATED_DURING_TASK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/ncap_aeb_result.json"
cat /tmp/ncap_aeb_result.json

echo "=== Export Complete ==="