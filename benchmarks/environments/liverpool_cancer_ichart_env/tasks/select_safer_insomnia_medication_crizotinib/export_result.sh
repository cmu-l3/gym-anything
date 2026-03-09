#!/system/bin/sh
echo "=== Exporting select_safer_insomnia_medication_crizotinib results ==="

OUTPUT_FILE="/sdcard/insomnia_safety_report.txt"
TASK_START_FILE="/sdcard/task_start_time.txt"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# Capture final state
screencap -p "$FINAL_SCREENSHOT"

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Check output file status
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content (limit size to prevent issues)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -n 10)
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if app is in foreground
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Create JSON result
# Note: Using manual JSON construction because 'jq' might not be on Android
echo "{" > /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"app_visible_at_end\": $APP_VISIBLE," >> /sdcard/task_result.json
# Escape quotes in content for JSON safety (basic)
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
echo "  \"file_content\": \"$ESCAPED_CONTENT\"," >> /sdcard/task_result.json
echo "  \"timestamp\": $(date +%s)" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="