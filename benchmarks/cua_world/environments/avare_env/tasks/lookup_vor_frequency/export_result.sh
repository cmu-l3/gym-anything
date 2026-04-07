#!/system/bin/sh
echo "=== Exporting lookup_vor_frequency results ==="

OUTPUT_FILE="/data/local/tmp/vor_frequency.txt"
START_TIME_FILE="/data/local/tmp/task_start_time.txt"
RESULT_JSON="/data/local/tmp/task_result.json"
FINAL_SCREENSHOT="/data/local/tmp/task_final.png"

# 1. Capture final state
screencap -p "$FINAL_SCREENSHOT" 2>/dev/null || true

# 2. Analyze Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"
CORRECT_FREQUENCY="false"
CORRECT_ID="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check timestamp (if supported by system stat, otherwise rely on setup clearing it)
    # Since setup deleted it, existence implies creation after setup start usually.
    # We can check strict modification time if available:
    TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    FILE_MOD=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || date +%s) # Fallback to now if stat fails
    
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content
    if echo "$FILE_CONTENT" | grep -q "116.8"; then
        CORRECT_FREQUENCY="true"
    fi
    if echo "$FILE_CONTENT" | grep -iq "OAK"; then
        CORRECT_ID="true"
    fi
fi

# 3. Check App State (is it still running?)
APP_RUNNING="false"
if pgrep -f "com.ds.avare" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# careful with JSON syntax in shell
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"correct_frequency\": $CORRECT_FREQUENCY," >> "$RESULT_JSON"
echo "  \"correct_id\": $CORRECT_ID," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"file_content_preview\": \"$(echo $FILE_CONTENT | head -c 100 | sed 's/"/\\"/g')\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"