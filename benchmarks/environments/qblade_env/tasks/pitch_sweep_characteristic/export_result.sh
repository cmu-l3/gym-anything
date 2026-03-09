#!/bin/bash
echo "=== Exporting pitch_sweep_characteristic result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file details
OUTPUT_PATH="/home/ga/Documents/projects/pitch_sweep_result.wpa"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"
IS_LARGER_THAN_INPUT="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified after task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if larger than input project (indicates data added)
    INPUT_SIZE=$(cat /tmp/input_project_size.txt 2>/dev/null || echo "0")
    if [ "$OUTPUT_SIZE" -gt "$INPUT_SIZE" ]; then
        IS_LARGER_THAN_INPUT="true"
    fi
    
    # Basic content check (if binary, simple grep might fail, but checking if it's not empty)
    # QBlade .wpa files are often binary/Qt archives, so size is the best proxy for content addition
fi

# Check if QBlade is still running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_larger_than_input": $IS_LARGER_THAN_INPUT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="