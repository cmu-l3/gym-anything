#!/system/bin/sh
echo "=== Exporting Motor Slip Results ==="

# 1. Capture final screen state
screencap -p /sdcard/tasks/final_screenshot.png

# 2. Check result file details
OUTPUT_FILE="/sdcard/tasks/motor_slip_result.txt"
START_TIME_FILE="/sdcard/tasks/task_start_time.txt"

FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check modification time against start time
    # Android stat format might vary, using simplistic check if available, 
    # otherwise relying on python verifier to check logic if timestamp unavailable in shell
    FILE_MOD_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null)
    TASK_START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null)
    
    if [ -n "$FILE_MOD_TIME" ] && [ -n "$TASK_START_TIME" ]; then
        if [ "$FILE_MOD_TIME" -gt "$TASK_START_TIME" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if stat is limited in this environment: assume true if exists 
        # (verifier will do stricter checks if it can access timestamps)
        FILE_CREATED_DURING_TASK="true" 
    fi
fi

# 3. Create JSON report
# We write manually to avoid dependency issues in minimal Android shell
echo "{" > /sdcard/tasks/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/tasks/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/tasks/task_result.json
echo "  \"file_content_raw\": \"$(echo $FILE_CONTENT | sed 's/"/\\"/g')\"," >> /sdcard/tasks/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/tasks/final_screenshot.png\"" >> /sdcard/tasks/task_result.json
echo "}" >> /sdcard/tasks/task_result.json

echo "=== Export complete ==="
cat /sdcard/tasks/task_result.json