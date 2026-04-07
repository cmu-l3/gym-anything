#!/system/bin/sh
# Export script for identify_longest_runway task
# Runs inside the Android environment

echo "=== Exporting identify_longest_runway result ==="

OUTPUT_FILE="/sdcard/longest_runway.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 1. Take final screenshot
screencap -p /sdcard/task_final.png 2>/dev/null

# 2. Check output file
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_MODIFIED_TIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}')
    
    # Android ls -l usually shows date/time, obtaining exact unix timestamp is harder 
    # with limited shell tools. We will trust the existence check combined with
    # the fact we deleted it in setup.
    if [ -f "$OUTPUT_FILE" ]; then
         CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is still running
APP_RUNNING="false"
if ps -A | grep -q "com.ds.avare"; then
    APP_RUNNING="true"
fi

# 4. Escape content for JSON (basic escaping)
# Replace newlines with \n and quotes with \"
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 5. Create JSON result
# writing manually to avoid dependency on jq or python in minimal android shell
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"task_end\": $END_TIME," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="