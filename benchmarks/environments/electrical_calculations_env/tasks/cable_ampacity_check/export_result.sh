#!/system/bin/sh
echo "=== Exporting cable_ampacity_check results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/sdcard/ampacity_result.txt"

# Capture final screenshot for VLM verification
screencap -p /sdcard/final_screenshot.png

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read content
    FILE_CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time
    FILE_MOD=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if app is in foreground
APP_FOCUSED="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_FOCUSED="true"
fi

# Create JSON result
# Note: Using manual JSON construction as 'jq' might not be available in minimal Android env
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"app_focused\": $APP_FOCUSED" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="