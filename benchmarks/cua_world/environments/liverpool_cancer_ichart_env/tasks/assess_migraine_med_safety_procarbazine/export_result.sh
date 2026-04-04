#!/system/bin/sh
echo "=== Exporting Migraine Safety Task Result ==="

REPORT_FILE="/sdcard/migraine_safety_report.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE="0"
TIMESTAMP_VALID="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || ls -l "$REPORT_FILE" | awk '{print $4}')
    
    # Simple check if file is newer than start time
    # (Android shell file comparison is limited, we rely on python verifier for strict timestamp check,
    # but we can check if file is non-empty here)
    if [ "$FILE_SIZE" -gt 0 ]; then
        TIMESTAMP_VALID="true"
    fi
fi

# 3. Create JSON result for verifier
# Note: JSON construction in sh is manual
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"timestamp_valid\": $TIMESTAMP_VALID," >> "$RESULT_JSON"
echo "  \"export_time\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"