#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Capture final state
screencap -p /sdcard/task_final.png

# Paths
OUTPUT_FILE="/sdcard/inductor_id.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# Check Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read file content safely (replace newlines with literal \n for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Get modification time (stat is available on Android 6+)
    FILE_MOD_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MOD_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if App is on top (simple check)
APP_FOCUSED="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_FOCUSED="true"
fi

# Construct JSON manually (sh on Android has limited JSON tools)
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"app_focused\": $APP_FOCUSED," >> "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="