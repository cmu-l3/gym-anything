#!/system/bin/sh
echo "=== Exporting task results ==="

# Paths
REPORT_FILE="/sdcard/interaction_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null || true

# 2. Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 3. Check Report File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
FILE_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MOD=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (escape quotes for JSON)
    FILE_CONTENT=$(cat "$REPORT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 4. Check if App is currently in foreground (optional hint)
APP_IN_FOREGROUND="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_IN_FOREGROUND="true"
fi

# 5. Create JSON Result
# We write to a temp file first then move, though on Android /sdcard is usually safe
echo "{
  \"file_exists\": $FILE_EXISTS,
  \"file_created_during_task\": $FILE_CREATED_DURING_TASK,
  \"file_size\": $FILE_SIZE,
  \"file_content\": \"$FILE_CONTENT\",
  \"app_in_foreground\": $APP_IN_FOREGROUND,
  \"task_start_time\": $TASK_START,
  \"export_time\": $(date +%s)
}" > "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="