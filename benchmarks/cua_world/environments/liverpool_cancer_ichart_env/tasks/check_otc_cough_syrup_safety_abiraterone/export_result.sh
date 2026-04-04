#!/system/bin/sh
echo "=== Exporting results for check_otc_cough_syrup_safety_abiraterone ==="

OUTPUT_FILE="/sdcard/cough_med_safety.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Check if output file exists and read content
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Get modification time (stat format is tricky on Android, using ls -l as fallback or date if stat missing)
    FILE_MOD_TIME=$(date -r "$OUTPUT_FILE" +%s 2>/dev/null)
    if [ -z "$FILE_MOD_TIME" ]; then
        # Fallback if date -r not supported
        FILE_MOD_TIME=$(ls -l "$OUTPUT_FILE" | awk '{print $4 " " $5}') # Very rough approximation
        FILE_MOD_TIME=0 # safer to rely on python verifier checking file creation if mtime hard to get in shell
    fi
fi

# 3. Get Task Start Time
START_TIME=0
if [ -f "$START_TIME_FILE" ]; then
    START_TIME=$(cat "$START_TIME_FILE")
fi

# 4. JSON Construction (Manual string building for busybox/shell compatibility)
# escaping newlines in content
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')

echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"start_time\": $START_TIME," >> "$RESULT_JSON"
echo "  \"file_mod_time\": \"$FILE_MOD_TIME\"," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Output for logging
cat "$RESULT_JSON"
echo "=== Export complete ==="