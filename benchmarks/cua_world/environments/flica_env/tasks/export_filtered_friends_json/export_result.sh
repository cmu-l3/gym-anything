#!/system/bin/sh
# Export script for export_filtered_friends_json task

echo "=== Exporting task results ==="

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Output File
OUTPUT_PATH="/sdcard/united_friends.json"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(ls -l "$OUTPUT_PATH" | awk '{print $5}')
    
    # Check modification time (simple check since Android `stat` varies)
    # We rely on the fact we deleted it in setup. If it exists, it was created.
    FILE_CREATED_DURING_TASK="true"
fi

# 3. Check App State
APP_RUNNING=$(pidof com.robert.fcView > /dev/null && echo "true" || echo "false")

# 4. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png

# 5. Create Result JSON
# We construct a JSON string manually to avoid dependency issues on minimal Android shells
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"output_size_bytes\": $OUTPUT_SIZE," >> /sdcard/task_result.json
echo "  \"app_was_running\": $APP_RUNNING" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="