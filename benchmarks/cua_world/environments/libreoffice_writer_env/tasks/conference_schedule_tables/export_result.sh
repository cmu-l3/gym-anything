#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Conference Schedule Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/conference_schedule.docx"

# 1. Check file existence and timestamp
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create JSON result
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

# 4. Close applications (graceful attempt)
pkill -f "soffice" || true
pkill -f "gedit" || true

echo "=== Export Complete ==="