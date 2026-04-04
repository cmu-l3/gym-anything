#!/system/bin/sh
echo "=== Exporting check_beta_blocker_with_osimertinib results ==="

ANSWER_FILE="/sdcard/answer.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot (evidence)
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved to /sdcard/final_screenshot.png"

# 2. Read Answer File
ANSWER_EXISTS="false"
ANSWER_CONTENT=""
if [ -f "$ANSWER_FILE" ]; then
    ANSWER_EXISTS="true"
    ANSWER_CONTENT=$(cat "$ANSWER_FILE")
    echo "Found answer file. Content: $ANSWER_CONTENT"
else
    echo "Answer file not found."
fi

# 3. Check File Timing (Anti-Gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$ANSWER_EXISTS" = "true" ] && [ -f "$START_TIME_FILE" ]; then
    # Android shell often lacks stat -c %Y, so we use file comparison or just existence logic
    # Since we deleted the file in setup, existence implies creation.
    # We can check if the file is non-empty.
    if [ -s "$ANSWER_FILE" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON Result
# We construct the JSON manually using echo since jq might not be on the device
echo "{" > "$RESULT_JSON"
echo "  \"answer_exists\": $ANSWER_EXISTS," >> "$RESULT_JSON"
echo "  \"answer_content\": \"$ANSWER_CONTENT\"," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "JSON result created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="