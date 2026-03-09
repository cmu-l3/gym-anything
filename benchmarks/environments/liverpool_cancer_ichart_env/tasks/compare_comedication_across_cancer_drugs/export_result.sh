#!/system/bin/sh
echo "=== Exporting task results ==="

REPORT_FILE="/sdcard/Download/clarithromycin_comparison.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Get task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi
TASK_END=$(date +%s)

# 3. Check report file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
FILE_SIZE="0"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (safely, first 1KB)
    FILE_CONTENT=$(head -c 1024 "$REPORT_FILE")
fi

# 4. Escape content for JSON (basic escaping for newlines and quotes)
# Note: Android shell might have limited sed, using simple approach
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 5. Create JSON result
# writing to temp file first
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"