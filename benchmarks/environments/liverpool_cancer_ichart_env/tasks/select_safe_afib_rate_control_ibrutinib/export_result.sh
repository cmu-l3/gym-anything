#!/system/bin/sh
echo "=== Exporting Ibrutinib AFib Safety Result ==="

# Define paths
OUTPUT_FILE="/sdcard/ibrutinib_afib_safety.txt"
JSON_RESULT="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Get task start time
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi

# Initialize variables
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"

# Check the output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Get modification time in seconds (Android stat supports %Y)
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take a final screenshot for evidence
screencap -p /sdcard/final_state.png

# Create JSON result manually (since jq might not be on device)
# We use a simple heredoc with careful escaping
echo "{" > "$JSON_RESULT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_RESULT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_RESULT"
echo "  \"file_mtime\": $FILE_MTIME," >> "$JSON_RESULT"
echo "  \"task_start\": $TASK_START," >> "$JSON_RESULT"
# Safe content embedding: replace newlines with \n and quotes with \"
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
echo "  \"file_content\": \"$SAFE_CONTENT\"" >> "$JSON_RESULT"
echo "}" >> "$JSON_RESULT"

echo "Export completed. Result saved to $JSON_RESULT"
cat "$JSON_RESULT"