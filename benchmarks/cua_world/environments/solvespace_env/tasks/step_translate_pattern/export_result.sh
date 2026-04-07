#!/bin/bash
echo "=== Exporting step_translate_pattern result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_GROUPS=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check for the expected output file
OUTPUT_PATH="/home/ga/Documents/SolveSpace/side_with_holes.slvs"
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FINAL_GROUPS="0"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Count groups in the new file
    FINAL_GROUPS=$(grep -c "AddGroup" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Copy the SLVS file to /tmp for the verifier to safely read
    cp "$OUTPUT_PATH" /tmp/output.slvs
    chmod 666 /tmp/output.slvs
fi

# Check if application is still running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "initial_group_count": $INITIAL_GROUPS,
    "final_group_count": $FINAL_GROUPS,
    "app_was_running": $APP_RUNNING
}
EOF

# Safely move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported results to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="