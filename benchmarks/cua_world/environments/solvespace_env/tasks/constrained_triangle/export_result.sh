#!/bin/bash
echo "=== Exporting constrained_triangle result ==="

source /workspace/scripts/task_utils.sh

# Target file path
OUTPUT_FILE="/home/ga/Documents/SolveSpace/right_triangle.slvs"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take a screenshot of the final state
take_screenshot /tmp/task_final.png

# Check if application is running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Check file existence and metadata
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the file to /tmp so the verifier can easily grab it with copy_from_env
    cp "$OUTPUT_FILE" /tmp/right_triangle.slvs
    chmod 666 /tmp/right_triangle.slvs
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING
}
EOF

# Move JSON to final accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="