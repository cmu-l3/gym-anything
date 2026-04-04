#!/system/bin/sh
# Export script for check_corticosteroid_with_dabrafenib
# Runs on Android device

echo "=== Exporting results ==="

REPORT_PATH="/sdcard/dabrafenib_dexamethasone_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# Defaults
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
TASK_START_TIME=0
FILE_MOD_TIME=0

# Read start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START_TIME=$(cat "$START_TIME_FILE")
fi

# Check report file
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (limit size to prevent issues)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 20)
    
    # Check modification time
    FILE_MOD_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null)
    
    if [ "$FILE_MOD_TIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Capture final screenshot explicitly for export (framework does this too, but redundancy is safe)
screencap -p /sdcard/final_screenshot.png

# Create JSON output
# Note: constructing JSON in shell is fragile, keeping it simple
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"report_content_preview\": \"$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"