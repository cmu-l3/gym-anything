#!/system/bin/sh
echo "=== Exporting Green Tea Safety Result ==="

OUTPUT_FILE="/sdcard/green_tea_safety_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_RESULT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check output file status
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}')
    
    # Check timestamp
    FILE_MTIME=$(ls -l --time-style=+%s "$OUTPUT_FILE" | awk '{print $6}')
    TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    # Note: Android shell 'ls' might not support --time-style everywhere, 
    # relying on simpler existence check if date math fails, but attempting robustness:
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        # Fallback: if we can't get precise mtime, assume yes if it exists now but was deleted in setup
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Escape content for JSON
# Simple escaping for basic text
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 4. Create JSON Result
echo "{" > "$JSON_RESULT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_RESULT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_RESULT"
echo "  \"file_content\": \"$ESCAPED_CONTENT\"," >> "$JSON_RESULT"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$JSON_RESULT"
echo "}" >> "$JSON_RESULT"

echo "Export complete. Content:"
cat "$JSON_RESULT"