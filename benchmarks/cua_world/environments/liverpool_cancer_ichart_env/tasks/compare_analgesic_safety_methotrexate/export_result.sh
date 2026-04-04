#!/system/bin/sh
echo "=== Exporting compare_analgesic_safety_methotrexate result ==="

OUTPUT_PATH="/sdcard/methotrexate_analgesic_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# Capture final screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null

# Read start time
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s 2>/dev/null || echo "0")

# Check output file
OUTPUT_EXISTS="false"
FILE_CONTENT=""
FILE_MODIFIED_TIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Check modification time (stat might vary on Android versions, using simple check)
    FILE_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MODIFIED_TIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Construct JSON result manually (no jq on minimal Android)
echo "{" > "$RESULT_JSON"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_mtime\": $FILE_MODIFIED_TIME," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="