#!/system/bin/sh
echo "=== Exporting check_ccb_interaction_with_olaparib results ==="

RESULT_FILE="/sdcard/tasks/interaction_result.txt"
START_TIME_FILE="/sdcard/tasks/task_start_time.txt"
JSON_OUTPUT="/sdcard/tasks/task_result.json"

# Capture final screenshot
screencap -p /sdcard/tasks/final_screenshot.png 2>/dev/null

# Get file stats
FILE_EXISTS="false"
FILE_CONTENT_LINE1=""
FILE_CONTENT_LINE2=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Read content safely
    FILE_CONTENT_LINE1=$(head -n 1 "$RESULT_FILE" | tr -d '\r\n')
    FILE_CONTENT_LINE2=$(sed -n '2p' "$RESULT_FILE" | tr -d '\r\n')

    # Check timestamps
    if [ -f "$START_TIME_FILE" ]; then
        START_TIME=$(cat "$START_TIME_FILE")
        FILE_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
        
        if [ "$FILE_TIME" -ge "$START_TIME" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Check if app is in foreground
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Build JSON manually (sh on Android is often limited)
# We use a temporary file construction approach
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"color_reported\": \"$FILE_CONTENT_LINE1\"," >> "$JSON_OUTPUT"
echo "  \"summary_reported\": \"$FILE_CONTENT_LINE2\"," >> "$JSON_OUTPUT"
echo "  \"app_visible_at_end\": $APP_VISIBLE," >> "$JSON_OUTPUT"
echo "  \"timestamp\": \"$(date)\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON content:"
cat "$JSON_OUTPUT"