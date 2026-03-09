#!/system/bin/sh
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/sdcard/antiepileptic_safety_report.txt"

# Check report file
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # read content (escape quotes for JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
screencap -p /sdcard/task_final.png

# Create JSON result
# We construct JSON manually because Android shell might lack jq or python
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"report_exists\": $REPORT_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"report_content\": \"$REPORT_CONTENT\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"