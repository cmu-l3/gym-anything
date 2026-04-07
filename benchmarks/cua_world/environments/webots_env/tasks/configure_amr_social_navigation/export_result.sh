#!/bin/bash
echo "=== Exporting configure_amr_social_navigation result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/amr_social_navigation.wbt"

FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Anti-gaming: Ensure file was created/modified after task started
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write metadata result JSON
cat > /tmp/amr_social_navigation_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/amr_social_navigation_result.json"
cat /tmp/amr_social_navigation_result.json

echo "=== Export Complete ==="