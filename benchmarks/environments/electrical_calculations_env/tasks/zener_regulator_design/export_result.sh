#!/system/bin/sh
echo "=== Exporting Zener Regulator Task Result ==="

TASK_DIR="/sdcard/tasks/zener_design"
RESULT_FILE="$TASK_DIR/result.txt"
START_TIME_FILE="$TASK_DIR/start_time.txt"
JSON_OUTPUT="/sdcard/tasks/zener_design/task_result.json"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_state.png"

# 2. Check if output file exists
if [ -f "$RESULT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Get file modification time
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Read content
    CONTENT=$(cat "$RESULT_FILE")
    # Escape newlines for JSON
    CONTENT_JSON=$(echo "$CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
else
    OUTPUT_EXISTS="false"
    FILE_MTIME="0"
    CONTENT_JSON=""
fi

# 3. Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START="0"
fi

# 4. Check if file was created during task
if [ "$OUTPUT_EXISTS" = "true" ] && [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
else
    CREATED_DURING_TASK="false"
fi

# 5. Check if App is in foreground (basic check)
# This dumps the window hierarchy and checks for the package name
DUMP_FILE="$TASK_DIR/window_dump.xml"
uiautomator dump "$DUMP_FILE" 2>/dev/null
if grep -q "com.hsn.electricalcalculations" "$DUMP_FILE"; then
    APP_VISIBLE="true"
else
    APP_VISIBLE="false"
fi

# 6. Create JSON Output
echo "{
  \"task_start\": $TASK_START,
  \"output_exists\": $OUTPUT_EXISTS,
  \"file_mtime\": $FILE_MTIME,
  \"created_during_task\": $CREATED_DURING_TASK,
  \"file_content\": \"$CONTENT_JSON\",
  \"app_visible\": $APP_VISIBLE,
  \"screenshot_path\": \"$TASK_DIR/final_state.png\",
  \"result_file_path\": \"$RESULT_FILE\"
}" > "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"