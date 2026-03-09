#!/system/bin/sh
# Export script for lumens_to_candela task
# Runs on Android device

echo "=== Exporting results ==="

TASK_DIR="/sdcard/tasks/lumens_to_candela"
RESULT_FILE="$TASK_DIR/result.txt"
SCREENSHOT_FILE="$TASK_DIR/screenshot.png"
JSON_OUT="$TASK_DIR/task_result.json"

# Get timestamps
END_TIME=$(date +%s)
START_TIME=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")

# Check Result File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    # Basic size check to ensure it's not empty
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
fi

# Check if App is running
APP_RUNNING="false"
if ps -A | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# Create JSON result
# Note: Using manual JSON construction as 'jq' might not be on Android
echo "{" > "$JSON_OUT"
echo "  \"timestamp\": $END_TIME," >> "$JSON_OUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_OUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUT"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$JSON_OUT"
echo "  \"app_running\": $APP_RUNNING" >> "$JSON_OUT"
echo "}" >> "$JSON_OUT"

echo "Export complete. JSON saved to $JSON_OUT"
cat "$JSON_OUT"