#!/bin/bash
# Export script for configure_tabletop_physics task

echo "=== Exporting configure_tabletop_physics result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot for evidence
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/physics_configured.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
    echo "Found output file: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)

# Generate JSON result file
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start_timestamp": $TASK_START,
    "output_path": "$OUTPUT_FILE"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="