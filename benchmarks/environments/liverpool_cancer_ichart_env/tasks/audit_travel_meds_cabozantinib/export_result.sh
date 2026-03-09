#!/system/bin/sh
# Export script for audit_travel_meds_cabozantinib
# Runs on Android device

echo "=== Exporting Task Result ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_FILE="/sdcard/travel_safety_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved."

# 2. Check File Existence & Timestamp
REPORT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
    TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape quotes for JSON)
    REPORT_CONTENT=$(cat "$REPORT_FILE" | sed 's/"/\\"/g' | tr '\n' '\\n')
fi

# 3. Check App State (is it running?)
APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct JSON Result
# Note: Android shell might have limited JSON tools, constructing string manually.
echo "{" > /sdcard/task_result.json
echo "  \"report_exists\": $REPORT_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"report_content_raw\": \"$REPORT_CONTENT\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json