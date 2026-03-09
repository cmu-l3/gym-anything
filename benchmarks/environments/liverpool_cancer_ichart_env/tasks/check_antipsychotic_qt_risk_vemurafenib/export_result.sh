#!/system/bin/sh
echo "=== Exporting Task Results ==="

RESULT_JSON="/sdcard/tasks/task_result.json"
OUTPUT_FILE="/sdcard/tasks/vemurafenib_quetiapine_check.txt"
START_TIME_FILE="/sdcard/tasks/task_start_time.txt"

# Get task start time
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi

# Check if output file exists
FILE_EXISTS=false
FILE_CREATED_DURING_TASK=false
FILE_CONTENT=""
FILE_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    # Get file modification time (stat format varies on Android, using ls -l hack or date if stat missing)
    # Using 'stat -c %Y' is standard on newer Android, fallback to date comparison if needed
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
    
    # Read file content safely (limit size)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -n 10)
fi

# Take final screenshot for evidence
screencap -p /sdcard/tasks/final_screenshot.png

# Create JSON result
# Note: JSON creation in shell is fragile, doing simple string concatenation
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"task_start_time\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_mtime\": $FILE_MTIME," >> "$RESULT_JSON"
echo "  \"file_content\": \"$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr '\n' '|')\"," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/tasks/final_screenshot.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="