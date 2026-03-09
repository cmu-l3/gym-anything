#!/system/bin/sh
echo "=== Exporting select_safe_hiccup_medication_crizotinib results ==="

# Define paths
OUTPUT_FILE="/sdcard/hiccup_safety.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_state.png"

# 1. Capture final state screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Gather file metadata
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # ls -l format varies on Android, using stat if available or simple check
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || ls -l "$OUTPUT_FILE" | awk '{print $4}')
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check modification time if possible (Android stat might differ, using existence logic relative to start)
    # Android shell often lacks full 'stat', so we rely on existence check + timestamp file created at start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "$CURRENT_TIME")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_CONTENT=""
    CREATED_DURING_TASK="false"
fi

# 3. Escape content for JSON
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 4. Write JSON result
echo "{
  \"file_exists\": $FILE_EXISTS,
  \"created_during_task\": $CREATED_DURING_TASK,
  \"file_content\": \"$SAFE_CONTENT\",
  \"task_start\": $TASK_START,
  \"task_end\": $CURRENT_TIME,
  \"screenshot_path\": \"$FINAL_SCREENSHOT\"
}" > "$RESULT_JSON"

echo "JSON result created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="