#!/system/bin/sh
echo "=== Exporting Task Results ==="

REPORT_PATH="/sdcard/domperidone_report.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || ls -l "$REPORT_PATH" | awk '{print $4}')
    # Read content, escaping quotes/newlines for JSON safety
    # Note: Android shell usually has limited tools, using simple cat and sed if available
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 3. Get Timestamp Info
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s 2>/dev/null || echo "0")

# 4. Construct JSON manually (Android shell often lacks jq)
# We write to a temp file then move to ensure atomicity
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"report_path\": \"$REPORT_PATH\"," >> "$RESULT_JSON"
echo "  \"report_size\": $REPORT_SIZE," >> "$RESULT_JSON"
echo "  \"start_timestamp\": \"$START_TIME\"," >> "$RESULT_JSON"
echo "  \"end_timestamp\": \"$CURRENT_TIME\"," >> "$RESULT_JSON"
echo "  \"report_content\": \"$REPORT_CONTENT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"