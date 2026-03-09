#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Output paths
REPORT_FILE="/sdcard/postop_screen.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# 2. Check if report file exists
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    # Check modification time (Android stat might differ, using ls -l as fallback if needed)
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
    FILE_MTIME="0"
fi

# 3. Check if file was created DURING the task (anti-gaming)
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
else
    CREATED_DURING_TASK="false"
fi

# 4. Check if app is still running (optional but good signal)
if pidof com.liverpooluni.ichartoncology > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 5. Take final screenshot
screencap -p /sdcard/task_final.png

# 6. Escape content for JSON (simple escape for newlines/quotes)
ESCAPED_CONTENT=$(echo "$REPORT_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 7. Construct JSON
echo "{
  \"report_exists\": $REPORT_EXISTS,
  \"report_content\": \"$ESCAPED_CONTENT\",
  \"file_created_during_task\": $CREATED_DURING_TASK,
  \"app_running\": $APP_RUNNING,
  \"task_start\": $TASK_START,
  \"task_end\": $TASK_END
}" > "$RESULT_JSON"

echo "JSON exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="