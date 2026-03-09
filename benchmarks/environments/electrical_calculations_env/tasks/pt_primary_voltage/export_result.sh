#!/system/bin/sh
# Export result script for pt_primary_voltage task

echo "=== Exporting Results ==="

# 1. capture final screenshot
screencap -p /sdcard/pt_final_screenshot.png

# 2. Check output file
OUTPUT_FILE="/sdcard/pt_result.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_MODIFIED_TIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 3. Get Task Start Time
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check if file was created during task
CREATED_DURING_TASK="false"
if [ "$FILE_MODIFIED_TIME" -gt "$START_TIME" ]; then
    CREATED_DURING_TASK="true"
fi

# 5. Check if app is running
APP_RUNNING="false"
if ps -A | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
# Note: JSON creation in sh is manual
JSON_FILE="/sdcard/task_result.json"

echo "{" > $JSON_FILE
echo "  \"output_exists\": $OUTPUT_EXISTS," >> $JSON_FILE
echo "  \"output_content\": \"$OUTPUT_CONTENT\"," >> $JSON_FILE
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> $JSON_FILE
echo "  \"app_running\": $APP_RUNNING," >> $JSON_FILE
echo "  \"screenshot_path\": \"/sdcard/pt_final_screenshot.png\"" >> $JSON_FILE
echo "}" >> $JSON_FILE

echo "Result exported to $JSON_FILE"
cat $JSON_FILE
echo "=== Export Complete ==="