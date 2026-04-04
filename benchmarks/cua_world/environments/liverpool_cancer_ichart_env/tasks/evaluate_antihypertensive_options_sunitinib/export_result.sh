#!/system/bin/sh
# Export script for Sunitinib Antihypertensive Evaluation task

echo "=== Exporting task results ==="

REPORT_PATH="/sdcard/sunitinib_bp_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Check File Stats
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || ls -l "$REPORT_PATH" | awk '{print $4}')
    
    # Read content for JSON (escape newlines/quotes)
    # Using sed to escape simplified for Android sh
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/"/\\"/g' | tr '\n' '|')
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null)
    TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if app is in foreground
PACKAGE="com.liverpooluni.ichartoncology"
APP_FOCUSED="false"
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_FOCUSED="true"
fi

# 4. Create JSON Result
# Note: constructing JSON manually in sh is fragile, keeping it simple
echo "{" > "$JSON_OUTPUT"
echo "\"output_exists\": $OUTPUT_EXISTS," >> "$JSON_OUTPUT"
echo "\"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "\"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "\"app_focused\": $APP_FOCUSED," >> "$JSON_OUTPUT"
echo "\"report_content_preview\": \"$REPORT_CONTENT\"," >> "$JSON_OUTPUT"
echo "\"timestamp\": $(date +%s)" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "JSON result exported to $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export complete ==="