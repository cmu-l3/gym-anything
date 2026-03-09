#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record output file info
OUTPUT_FILE="/home/ga/Documents/projects/lab_power_curve.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
CONTENT_PREVIEW=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read first 20 lines for verification (headers + data)
    # Encode in base64 to safely pass JSON
    CONTENT_PREVIEW=$(head -n 20 "$OUTPUT_FILE" | base64 -w 0)
fi

# Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "content_preview_base64": "$CONTENT_PREVIEW",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="