#!/system/bin/sh
echo "=== Exporting task results ==="

OUTPUT_FILE="/sdcard/cisplatin_pain_audit.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Capture final state screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Get file stats and content
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g') 
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check timestamp against start time
    if [ -f "$START_TIME_FILE" ]; then
        START_TIME=$(cat "$START_TIME_FILE")
        if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
            CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if start time missing: assume true if file exists now
        CREATED_DURING_TASK="true" 
    fi
fi

# 3. Check if app is in foreground (simple dump check)
APP_VISIBLE="false"
if dumpsys window | grep -q "mCurrentFocus.*com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# 4. Construct JSON result
# Note: Manual JSON construction is safer in minimal Android shells than jq
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"app_visible\": $APP_VISIBLE," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"