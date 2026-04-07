#!/system/bin/sh
# Export script for select_landing_runway task
# Collects the report file, timestamps, and final screenshot

echo "=== Exporting task results ==="

REPORT_FILE="/sdcard/runway_report.txt"
TASK_START_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png 2>/dev/null

# 2. Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 3. Check report file
FILE_EXISTS="false"
FILE_MTIME=0
CONTENT_LINE1=""
CONTENT_LINE2=""
CONTENT_LINE3=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
    
    # Read content safely
    CONTENT_LINE1=$(head -n 1 "$REPORT_FILE" 2>/dev/null | tr -d '\r')
    CONTENT_LINE2=$(head -n 2 "$REPORT_FILE" | tail -n 1 2>/dev/null | tr -d '\r')
    CONTENT_LINE3=$(head -n 3 "$REPORT_FILE" | tail -n 1 2>/dev/null | tr -d '\r')
    
    # Check timestamp validity
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON payload
# Note: Android shell usually has limited JSON tools, so we construct manually
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_mtime\": $FILE_MTIME," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"content_runway\": \"$CONTENT_LINE1\"," >> "$RESULT_JSON"
echo "  \"content_length\": \"$CONTENT_LINE2\"," >> "$RESULT_JSON"
echo "  \"content_count\": \"$CONTENT_LINE3\"," >> "$RESULT_JSON"
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "JSON exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="