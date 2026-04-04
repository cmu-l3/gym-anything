#!/system/bin/sh
# Export script for EGFR Comparison Task
# Runs on Android device

echo "=== Exporting Results ==="

RESULT_FILE="/sdcard/task_result.json"
REPORT_FILE="/sdcard/egfr_amiodarone_comparison.md"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Check if Report Exists
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | sed 's/"/\\"/g' | tr '\n' '\\n')
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$REPORT_FILE")
    START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_TIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 3. Create JSON Result
# We construct JSON manually using echo since jq is likely not on the android device
echo "{" > "$RESULT_FILE"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_FILE"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_FILE"
echo "  \"report_size\": $REPORT_SIZE," >> "$RESULT_FILE"
echo "  \"report_content\": \"$REPORT_CONTENT\"," >> "$RESULT_FILE"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

echo "Export complete. Result saved to $RESULT_FILE"
cat "$RESULT_FILE"