#!/system/bin/sh
# Export script for CDK4/6 Class Audit Task
# Runs on Android device

echo "=== Exporting Task Results ==="

RESULT_FILE="/sdcard/cdk46_class_audit.txt"
JSON_OUTPUT="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Get Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME="0"

# 3. Check Report File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Android `stat` might be limited, try to get mtime
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$RESULT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 4. Create JSON Result
# We construct JSON manually using echo because `jq` might not be on the device
echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"task_end\": $TASK_END," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"final_screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"