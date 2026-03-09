#!/system/bin/sh
# Export script for resonant_frequency_lc task

echo "=== Exporting resonant_frequency_lc results ==="

TASK_DIR="/sdcard/tasks/resonant_frequency_lc"
RESULT_FILE="$TASK_DIR/result.txt"
START_TIME_FILE="$TASK_DIR/task_start_time.txt"
JSON_OUTPUT="$TASK_DIR/task_result.json"
PACKAGE="com.hsn.electricalcalculations"

# Capture final screenshot
screencap -p "$TASK_DIR/final_state.png" 2>/dev/null || true

# Get task timings
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# Check result file status
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created/modified DURING the task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_FRESH="true"
    else
        FILE_FRESH="false"
    fi
    
    # Read content (first line)
    FILE_CONTENT=$(cat "$RESULT_FILE" | head -n 1)
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_FRESH="false"
    FILE_CONTENT=""
fi

# Check if app is currently in foreground/running
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Create JSON result
# Note: constructing JSON manually in shell since jq might not be on Android
echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"task_end\": $TASK_END," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_fresh\": $FILE_FRESH," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"app_running\": $APP_RUNNING," >> "$JSON_OUTPUT"
echo "  \"final_screenshot_path\": \"$TASK_DIR/final_state.png\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

# Ensure permissions
chmod 666 "$JSON_OUTPUT" 2>/dev/null || true

echo "Result exported to $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export complete ==="