#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Paths
REPORT_PATH="/sdcard/Documents/flight_search_report.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Collect File Statistics
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Verify timestamp
    if [ -f "$START_TIME_FILE" ]; then
        START_TIME=$(cat "$START_TIME_FILE")
        if [ "$REPORT_MTIME" -gt "$START_TIME" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if start time missing (shouldn't happen)
        FILE_CREATED_DURING_TASK="true" 
    fi
fi

# 3. Create JSON Result
# formatting manually as 'jq' might not be available on Android shell
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"report_size\": $REPORT_SIZE," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"," >> "$RESULT_JSON"
echo "  \"report_path\": \"$REPORT_PATH\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"