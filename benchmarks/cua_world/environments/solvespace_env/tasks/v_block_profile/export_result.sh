#!/bin/bash
echo "=== Exporting v_block_profile result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/SolveSpace/v_block_profile.slvs"

# Take final screenshot
take_screenshot /tmp/task_final.png

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy the SLVS file to /tmp so copy_from_env can grab it reliably
    cp "$OUTPUT_PATH" /tmp/v_block_profile_eval.slvs
    chmod 666 /tmp/v_block_profile_eval.slvs
fi

APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON metadata result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "initial_screenshot": "/tmp/task_initial.png",
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="