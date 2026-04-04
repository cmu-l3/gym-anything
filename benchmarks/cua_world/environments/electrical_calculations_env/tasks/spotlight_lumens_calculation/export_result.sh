#!/system/bin/sh
echo "=== Exporting Spotlight Lumens Results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null || true

# 2. Collect Task Data
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULT_FILE="/sdcard/spotlight_results.txt"

# Check result file details
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    # Read content safely
    FILE_CONTENT=$(cat "$RESULT_FILE" | sed 's/"/\\"/g')
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_CONTENT=""
fi

# Check if app is in foreground (simple check)
APP_FOCUSED=$(dumpsys window | grep mCurrentFocus | grep "com.hsn.electricalcalculations" && echo "true" || echo "false")

# 3. Generate JSON Result
# We write to a temp file first to avoid read/write race conditions
TEMP_JSON="/sdcard/task_result_temp.json"

echo "{" > $TEMP_JSON
echo "  \"task_start\": $TASK_START," >> $TEMP_JSON
echo "  \"task_end\": $TASK_END," >> $TEMP_JSON
echo "  \"file_exists\": $FILE_EXISTS," >> $TEMP_JSON
echo "  \"file_size\": $FILE_SIZE," >> $TEMP_JSON
echo "  \"file_mtime\": $FILE_MTIME," >> $TEMP_JSON
echo "  \"file_content\": \"$FILE_CONTENT\"," >> $TEMP_JSON
echo "  \"app_focused\": $APP_FOCUSED" >> $TEMP_JSON
echo "}" >> $TEMP_JSON

# Move to final location
mv $TEMP_JSON /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"