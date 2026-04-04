#!/system/bin/sh
echo "=== Exporting Task Results ==="

OUTPUT_FILE="/sdcard/lorlatinib_macrolide_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Read task timing
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check output file status
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Check modification time
    FILE_MOD_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MOD_TIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON result
# Note: We construct JSON manually since 'jq' might not be on the Android image
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="