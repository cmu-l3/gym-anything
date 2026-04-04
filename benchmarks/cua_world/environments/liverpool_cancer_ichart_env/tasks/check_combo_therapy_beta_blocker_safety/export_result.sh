#!/system/bin/sh
# Export script for check_combo_therapy_beta_blocker_safety task

echo "=== Exporting Results ==="

REPORT_PATH="/sdcard/combo_safety_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Take final screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Final screenshot saved"

# 2. Check if report exists
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content, escaping quotes/backslashes for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Check timestamp
    FILE_MOD_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    TASK_START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MOD_TIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
    FILE_CREATED_DURING_TASK="false"
fi

# 3. Create JSON output
# Note: Android shell usually has limited printf/echo support, careful with JSON construction.
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"report_content\": \"$REPORT_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "JSON result created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="