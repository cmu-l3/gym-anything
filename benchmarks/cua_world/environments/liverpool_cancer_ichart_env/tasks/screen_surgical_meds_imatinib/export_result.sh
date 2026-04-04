#!/system/bin/sh
# Export script for screen_surgical_meds_imatinib
# Runs on Android device via ADB shell

echo "=== Exporting Surgical Meds Screen Results ==="

REPORT_FILE="/sdcard/surgical_screen_imatinib.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"

# 1. Capture final screenshot
screencap -p "$FINAL_SCREENSHOT" 2>/dev/null

# 2. Check if report file exists
FILE_EXISTS="false"
FILE_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    # Read file content, escaping quotes and newlines for JSON
    # Note: Android shell usually has limited sed/awk, so we keep it simple
    FILE_CONTENT=$(cat "$REPORT_FILE")
fi

# 3. Check timestamps (Anti-gaming)
TASK_START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MOD_TIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ]; then
    # Simple check: is file time > start time?
    # Note: Using string comparison if numeric fails in minimal shell, but stat %Y output is numeric
    if [ "$FILE_MOD_TIME" -gt "$TASK_START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON output
# We construct JSON manually because 'jq' is rarely on Android
# Use echo to build the JSON string carefully

# Escape content for JSON (basic)
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_path\": \"$REPORT_FILE\"," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Exported result to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="