#!/system/bin/sh
# Export script for Compare Antihistamine Safety task

echo "=== Exporting Results ==="

RESULT_JSON="/sdcard/task_result.json"
REPORT_PATH="/sdcard/dasatinib_antihistamine_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Get task start time
TASK_START=$(cat $START_TIME_FILE 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Check if report file exists
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    # Escape quotes for JSON
    REPORT_CONTENT_JSON=$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')
    
    # Check modification time (Android ls -l usually shows date/time, stat might be available)
    # We'll rely on the file existing and containing correct data as primary proof
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
else
    REPORT_EXISTS="false"
    REPORT_CONTENT_JSON=""
    FILE_SIZE="0"
fi

# Take final screenshot for evidence
screencap -p /sdcard/final_screenshot.png 2>/dev/null

# Construct JSON result
# Note: constructing JSON manually in shell is fragile but standard for these embedded environments
echo "{" > "$RESULT_JSON"
echo "\"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "\"task_end\": $CURRENT_TIME," >> "$RESULT_JSON"
echo "\"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "\"report_content\": \"$REPORT_CONTENT_JSON\"," >> "$RESULT_JSON"
echo "\"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "\"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Exported to $RESULT_JSON"
cat "$RESULT_JSON"