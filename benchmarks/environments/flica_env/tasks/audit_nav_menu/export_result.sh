#!/system/bin/sh
echo "=== Exporting Audit Navigation Menu Result ==="

OUTPUT_FILE="/sdcard/menu_audit.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Get task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 3. Analyze output file
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
LINE_COUNT=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Count lines (simple check for content)
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
fi

# 4. Create JSON result
# Note: We don't verify content here; python verifier will pull the actual text file
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"line_count\": $LINE_COUNT" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"