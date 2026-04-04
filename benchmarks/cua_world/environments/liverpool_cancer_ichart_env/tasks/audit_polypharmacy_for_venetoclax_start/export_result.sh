#!/system/bin/sh
echo "=== Exporting Venetoclax Audit Results ==="

RESULT_FILE="/sdcard/task_result.json"
CSV_FILE="/sdcard/venetoclax_audit.csv"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Get file stats
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_TIME=0

if [ -f "$CSV_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CSV_FILE")
    FILE_MODIFIED_TIME=$(stat -c %Y "$CSV_FILE")
fi

# 3. Read Start Time
START_TIME=0
if [ -f "$START_TIME_FILE" ]; then
    START_TIME=$(cat "$START_TIME_FILE")
fi

# 4. Check if file was created/modified during task
CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_MODIFIED_TIME" -ge "$START_TIME" ]; then
    CREATED_DURING_TASK="true"
fi

# 5. Create JSON Result
# Note: We construct JSON manually using echo since jq might not be available on minimal Android
echo "{" > "$RESULT_FILE"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_FILE"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_FILE"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_FILE"
echo "  \"csv_path\": \"$CSV_FILE\"," >> "$RESULT_FILE"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> "$RESULT_FILE"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="