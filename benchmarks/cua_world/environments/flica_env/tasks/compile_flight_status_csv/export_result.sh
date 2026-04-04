#!/system/bin/sh
echo "=== Exporting compile_flight_status_csv results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/sdcard/flight_report.csv"

# Capture final screenshot
screencap -p /sdcard/final_screenshot.png

# Check output file status
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
CSV_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content for JSON (escape quotes and newlines for simple JSON embedding)
    # Note: On Android shell, complex JSON creation can be tricky, so we keep it simple
    # We will rely on the verifier reading the raw CSV file separately
fi

# Check if app is in foreground (simple check using dumpsys)
APP_VISIBLE="false"
if dumpsys window windows | grep -q "mCurrentFocus.*com.robert.fcView"; then
    APP_VISIBLE="true"
fi

# Create a simple JSON result file
# We construct it manually to avoid dependency on python/jq in the android env
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_size\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"app_visible\": $APP_VISIBLE" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"