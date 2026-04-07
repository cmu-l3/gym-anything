#!/system/bin/sh
echo "=== Exporting retrieve_route_eta_duration results ==="

OUTPUT_FILE="/sdcard/trip_duration.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Capture final screenshot for verification
screencap -p "$FINAL_SCREENSHOT" 2>/dev/null

# Get task timing
TASK_END=$(date +%s)
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi

# Check output file status
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Get modification time (stat might vary on Android versions, using ls -l as backup)
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# Determine if file was created during task
CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Check if app is running
APP_RUNNING="false"
if dumpsys window windows | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
fi

# Create JSON output manually (Android shell has limited json tools)
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"output_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"output_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result stored in $RESULT_JSON"
cat "$RESULT_JSON"