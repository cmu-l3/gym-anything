#!/system/bin/sh
# export_compare_sildenafil.sh
# Export results for Sildenafil comparison task

echo "=== Exporting Results ==="

REPORT_PATH="/sdcard/sildenafil_comparison.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 2. Check Report File
FILE_EXISTS=false
FILE_CREATED_DURING_TASK=false
CONTENT=""
FILE_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    # Anti-gaming: Check if file was modified after task start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
    
    # Read content safely
    CONTENT=$(cat "$REPORT_PATH")
fi

# 3. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png

# 4. Create JSON Result
# We construct JSON manually using echo to avoid dependency issues in minimal Android shell
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
# Escape newlines in content for JSON validity
CLEAN_CONTENT=$(echo "$CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "  \"content\": \"$CLEAN_CONTENT\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"