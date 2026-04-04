#!/system/bin/sh
echo "=== Exporting Ribociclib Risk Analysis Result ==="

OUTPUT_FILE="/sdcard/ribociclib_risk_analysis.txt"
RESULT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"

# 1. Take final screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Collect Data
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Android ls -l usually shows date, stat might not be available or standard. 
    # We will trust existence + content for now, verifier checks logic.
    FILE_MTIME=$(date +%s) # Approximation since stat is flaky on minimal Android shells
fi

# Escape content for JSON (simple/naive escaping)
# Replace newlines with \n and quotes with \"
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 3. Create JSON Result
echo "{" > "$RESULT_JSON"
echo "  \"timestamp\": $CURRENT_TIME," >> "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"