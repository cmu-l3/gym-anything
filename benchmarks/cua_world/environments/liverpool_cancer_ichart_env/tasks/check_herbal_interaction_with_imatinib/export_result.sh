#!/system/bin/sh
echo "=== Exporting check_herbal_interaction_with_imatinib result ==="

# Define paths
RESULT_FILE="/sdcard/interaction_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# Check result file details
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT_B64=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || ls -l "$RESULT_FILE" | awk '{print $4}')
    
    # Check modification time against start time
    # Android stat format can vary, using date comparison if stat mtime fails
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Encode content to base64 to safely embed in JSON (handle newlines/quotes)
    FILE_CONTENT_B64=$(cat "$RESULT_FILE" | base64 | tr -d '\n')
fi

# Take final screenshot
screencap -p /sdcard/task_final.png

# Check if app is in foreground
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Create JSON output manually (Android sh has no jq)
echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"task_end\": $TASK_END," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"app_visible\": $APP_VISIBLE," >> "$JSON_OUTPUT"
echo "  \"file_content_b64\": \"$FILE_CONTENT_B64\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Result exported to $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export complete ==="