#!/system/bin/sh
echo "=== Exporting PPI Comparison Result ==="

REPORT_PATH="/sdcard/ppi_switch_recommendation.txt"
SCREENSHOT_PATH="/sdcard/ppi_comparison_table.png"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# Get Task Start Time
START_TIME=0
if [ -f "$START_TIME_FILE" ]; then
    START_TIME=$(cat "$START_TIME_FILE")
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (limit size and escape for JSON)
    # Using head to prevent massive file reads
    RAW_CONTENT=$(cat "$REPORT_PATH" | head -n 20)
    # Simple JSON escaping for sh
    REPORT_CONTENT=$(echo "$RAW_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null)
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check Agent's Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null)
    if [ "$SCREENSHOT_MTIME" -le "$START_TIME" ]; then
        # If screenshot is old (pre-dating task), count as not existing/invalid
        SCREENSHOT_EXISTS="false" 
    fi
fi

# Capture System Final Screenshot (for trajectory VLM fallback)
screencap -p /sdcard/final_state.png

# Construct JSON manually (sh on Android often lacks jq)
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$RESULT_JSON"
echo "  \"report_content\": \"$REPORT_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

chmod 666 "$RESULT_JSON" 2>/dev/null

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"