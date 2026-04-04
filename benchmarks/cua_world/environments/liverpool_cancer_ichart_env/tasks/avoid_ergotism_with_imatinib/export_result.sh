#!/system/bin/sh
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/sdcard/migraine_safety_check.txt"

# Take final screenshot
screencap -p /sdcard/task_final.png

# Check if result file exists and get metadata
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
fi

# Check if app is running
APP_RUNNING="false"
if ps -A | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# Create JSON result
# Note: Using manual JSON construction because 'jq' might not be on Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_mtime\": $FILE_MTIME," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="