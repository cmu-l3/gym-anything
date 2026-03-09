#!/system/bin/sh
echo "=== Exporting heater_power_derating results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/sdcard/Download/derated_power.txt"

# 1. Check Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content (first line)
    FILE_CONTENT=$(head -n 1 "$OUTPUT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check App State (is it running?)
APP_RUNNING="false"
if ps -A | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# 3. Take Final Screenshot
screencap -p /sdcard/task_final.png

# 4. Create JSON Result
# We construct JSON manually using echo since jq might not be available on Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="