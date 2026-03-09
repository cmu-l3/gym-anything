#!/system/bin/sh
echo "=== Exporting check_hepc_regimen_sorafenib result ==="

OUTPUT_FILE="/sdcard/sorafenib_hepc_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_RESULT="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 3. Check Output File
FILE_EXISTS="false"
FILE_CREATED_DURING="false"
FILE_CONTENT=""
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || ls -l "$OUTPUT_FILE" | awk '{print $4}')
    
    # Check modification time vs start time
    # Android 'stat' might be limited, so we rely on simple existence check relative to setup clearing it
    # Since setup deleted it, existence implies creation during task
    FILE_CREATED_DURING="true"
    
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 4. Check App State
APP_RUNNING="false"
if pidof com.liverpooluni.ichartoncology > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
# Note: Manually constructing JSON as 'jq' might not be on Android
echo "{" > "$JSON_RESULT"
echo "  \"task_start\": $TASK_START," >> "$JSON_RESULT"
echo "  \"output_file_exists\": $FILE_EXISTS," >> "$JSON_RESULT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING," >> "$JSON_RESULT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_RESULT"
echo "  \"app_running\": $APP_RUNNING," >> "$JSON_RESULT"
echo "  \"timestamp\": \"$(date)\"" >> "$JSON_RESULT"
echo "}" >> "$JSON_RESULT"

echo "Export complete. Result saved to $JSON_RESULT"
cat "$JSON_RESULT"