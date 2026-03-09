#!/system/bin/sh
echo "=== Exporting Task Results ==="

REPORT_PATH="/sdcard/regorafenib_categories_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Check Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (escape quotes for JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate JSON Output
# Note: creating clean JSON in shell can be tricky, using simple concatenation
echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"report_content_escaped\": \"$REPORT_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"final_screenshot\": \"/sdcard/final_screenshot.png\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Result exported to $JSON_OUTPUT"
cat "$JSON_OUTPUT"