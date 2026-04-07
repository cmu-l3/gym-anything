#!/bin/bash
echo "=== Exporting parametric_warren_truss_2d result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing application
take_screenshot /tmp/task_final.png

TARGET_FILE="/home/ga/Documents/SolveSpace/warren_truss.slvs"

# Check if file exists and was created/modified during the task
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy the SLVS file to /tmp so the verifier can access it securely
    cp "$TARGET_FILE" /tmp/warren_truss_result.slvs
    chmod 666 /tmp/warren_truss_result.slvs
fi

# Check if application was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result block
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "slvs_path": "/tmp/warren_truss_result.slvs"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="