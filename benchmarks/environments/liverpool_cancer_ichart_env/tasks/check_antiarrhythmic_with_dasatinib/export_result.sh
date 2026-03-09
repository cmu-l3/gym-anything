#!/system/bin/sh
# export_check_antiarrhythmic.sh
# Exports results for verification

echo "=== Exporting check_antiarrhythmic_with_dasatinib results ==="

RESULT_FILE="/sdcard/task_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final_state.png

# 2. Gather File Statistics
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Read content safely (escape quotes for JSON)
    # Using cat and sed to escape double quotes and newlines for JSON embedding
    FILE_CONTENT=$(cat "$RESULT_FILE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 3. Get Task Start Time
TASK_START_TIME="0"
if [ -f "$START_TIME_FILE" ]; then
    TASK_START_TIME=$(cat "$START_TIME_FILE")
fi

# 4. Check if app is in foreground (simple heuristic)
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# 5. Construct JSON Result
# We construct the JSON manually using echo to avoid external dependencies like jq
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"file_mtime\": $FILE_MTIME," >> "$JSON_OUTPUT"
echo "  \"task_start_time\": $TASK_START_TIME," >> "$JSON_OUTPUT"
echo "  \"app_visible_at_end\": $APP_VISIBLE," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$FILE_CONTENT\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"