#!/system/bin/sh
# export_neutral_current.sh
# Runs on Android device to collect evidence after task

echo "=== Exporting Neutral Current Results ==="

# 1. Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Text Output File
TEXT_FILE="/sdcard/neutral_current.txt"
TEXT_EXISTS="false"
TEXT_VALUE=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    TEXT_VALUE=$(cat "$TEXT_FILE")
    
    # Check modification time
    FILE_MOD=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Screenshot Output
IMG_FILE="/sdcard/neutral_result.png"
IMG_EXISTS="false"
if [ -f "$IMG_FILE" ]; then
    # Check if it has content (size > 0)
    SIZE=$(stat -c %s "$IMG_FILE" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 0 ]; then
        IMG_EXISTS="true"
    fi
fi

# 4. Check if App is running (foreground)
APP_RUNNING="false"
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# 5. Capture Final State Screenshot (System-level evidence)
screencap -p /sdcard/task_final.png

# 6. Create JSON Report
# Note: constructing JSON manually in shell to avoid dependency issues
JSON_PATH="/sdcard/task_result.json"
echo "{" > "$JSON_PATH"
echo "  \"task_start\": $TASK_START," >> "$JSON_PATH"
echo "  \"task_end\": $TASK_END," >> "$JSON_PATH"
echo "  \"text_exists\": $TEXT_EXISTS," >> "$JSON_PATH"
echo "  \"text_value\": \"$TEXT_VALUE\"," >> "$JSON_PATH"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_PATH"
echo "  \"screenshot_exists\": $IMG_EXISTS," >> "$JSON_PATH"
echo "  \"app_running\": $APP_RUNNING" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "Result JSON saved to $JSON_PATH"
cat "$JSON_PATH"
echo "=== Export Complete ==="