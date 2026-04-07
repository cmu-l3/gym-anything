#!/bin/bash
echo "=== Exporting build_custom_diffbot result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/my_robot.wbt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write result JSON
cat > /tmp/build_custom_diffbot_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start_timestamp": $TASK_START,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date +%s)"
}
EOF

cat /tmp/build_custom_diffbot_result.json
echo "=== Export Complete ==="