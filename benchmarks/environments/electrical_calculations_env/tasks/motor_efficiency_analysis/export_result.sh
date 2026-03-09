#!/system/bin/sh
# Export script for motor_efficiency_analysis task

echo "=== Exporting Task Results ==="

# 1. Capture final state
screencap -p /sdcard/task_final.png
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check output file
OUTPUT_PATH="/sdcard/efficiency_report.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if app is running
PACKAGE="com.hsn.electricalcalculations"
APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# Note: constructing JSON manually in shell is fragile, keeping it simple
# We escape double quotes in file content to prevent JSON errors
CLEAN_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')

echo "{
    \"task_start\": $TASK_START,
    \"task_end\": $TASK_END,
    \"file_exists\": $FILE_EXISTS,
    \"file_created_during_task\": $FILE_CREATED_DURING_TASK,
    \"file_content\": \"$CLEAN_CONTENT\",
    \"app_running\": $APP_RUNNING
}" > /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"