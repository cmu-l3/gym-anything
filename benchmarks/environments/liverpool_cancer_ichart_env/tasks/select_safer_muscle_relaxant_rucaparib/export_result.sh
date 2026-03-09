#!/system/bin/sh
# Export script for select_safer_muscle_relaxant_rucaparib task
# Runs on Android via adb shell

echo "=== Exporting Task Results ==="

RESULT_FILE="/sdcard/muscle_relaxant_safety.txt"
JSON_OUTPUT="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_state.png"

# 1. Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Check result file details
FILE_EXISTS=false
FILE_SIZE=0
FILE_CONTENT=""
CREATED_AFTER_START=false

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$RESULT_FILE")
    FILE_CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_AFTER_START=true
    fi
fi

# 3. Construct JSON result
# Note: We construct JSON manually as 'jq' might not be on the android image
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"created_during_task\": $CREATED_AFTER_START," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
# Escape newlines for JSON string safety
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"timestamp\": $(date +%s)" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "JSON result created at $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export Complete ==="