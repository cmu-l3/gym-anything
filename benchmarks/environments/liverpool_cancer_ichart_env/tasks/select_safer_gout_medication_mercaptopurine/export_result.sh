#!/system/bin/sh
echo "=== Exporting Task Results ==="

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Get Task Timestamps
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 3. Check Output File
OUTPUT_FILE="/sdcard/gout_safety_check.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # On Android, stat might behave differently depending on version (toybox vs toolbox)
    # We try to get mod time. If stat -c %Y fails, we assume file is new since we deleted it in setup.
    FILE_MOD_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "$END_TIME")
fi

# 4. JSON Construction (Manual construction since jq/python might not be on device)
# We escape newlines in content for JSON validity
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $START_TIME," >> /sdcard/task_result.json
echo "  \"task_end\": $END_TIME," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_mod_time\": $FILE_MOD_TIME," >> /sdcard/task_result.json
echo "  \"file_content\": \"$ESCAPED_CONTENT\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"