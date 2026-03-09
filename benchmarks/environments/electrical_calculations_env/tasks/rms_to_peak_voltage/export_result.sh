#!/system/bin/sh
# Export script for rms_to_peak_voltage task

echo "=== Exporting Results ==="

TASK_DIR="/sdcard/tasks"
RESULT_JSON="$TASK_DIR/task_result.json"
TXT_FILE="$TASK_DIR/peak_voltage.txt"
PNG_FILE="$TASK_DIR/rms_to_peak_result.png"

# Get task start time
START_TIME=$(cat /sdcard/tasks/rms_to_peak_voltage/start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Check text file
TXT_EXISTS="false"
TXT_CONTENT=""
if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(cat "$TXT_FILE")
fi

# Check screenshot
PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Check app state (is it still running?)
PACKAGE="com.hsn.electricalcalculations"
APP_RUNNING="false"
if pidof com.hsn.electricalcalculations > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# Note: constructing JSON manually in shell as jq might not be available
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"task_end\": $END_TIME," >> "$RESULT_JSON"
echo "  \"txt_exists\": $TXT_EXISTS," >> "$RESULT_JSON"
echo "  \"txt_content\": \"$TXT_CONTENT\"," >> "$RESULT_JSON"
echo "  \"png_exists\": $PNG_EXISTS," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Save a final system screenshot as backup
screencap -p /sdcard/tasks/final_system_state.png

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="