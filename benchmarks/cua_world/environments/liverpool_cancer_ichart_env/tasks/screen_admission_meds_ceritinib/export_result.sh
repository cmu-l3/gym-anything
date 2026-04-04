#!/system/bin/sh
echo "=== Exporting screen_admission_meds_ceritinib result ==="

# Define paths
REPORT_FILE="/sdcard/ceritinib_screening_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Check File Existence and Timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Read content (cat is safe for small text files)
    FILE_CONTENT=$(cat "$REPORT_FILE")
    
    # check timestamp if possible (stat might not be available on all android shells, using ls -l workaround or similar if needed)
    # simpler anti-gaming: check if file is newer than start_time file
    if [ -f "$START_TIME_FILE" ]; then
        if [ "$REPORT_FILE" -nt "$START_TIME_FILE" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if start time missing: assume true if exists (weak check)
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create JSON Result
# We construct JSON manually using echo to avoid python dependencies on Android
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
# Escape newlines in content for valid JSON
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "  \"file_content\": \"$ESCAPED_CONTENT\"," >> "$RESULT_JSON"
echo "  \"final_screenshot\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"