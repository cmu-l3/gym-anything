#!/bin/bash
# Export script for configure_airdrop_damping_physics task

echo "=== Exporting configure_airdrop_damping_physics result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Desktop/airdrop_configured.wbt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if the file was actually saved during the task session
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write summary JSON
cat > /tmp/configure_airdrop_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE"
}
EOF

chmod 666 /tmp/configure_airdrop_result.json 2>/dev/null || true

echo "Result saved to /tmp/configure_airdrop_result.json"
cat /tmp/configure_airdrop_result.json
echo "=== Export Complete ==="