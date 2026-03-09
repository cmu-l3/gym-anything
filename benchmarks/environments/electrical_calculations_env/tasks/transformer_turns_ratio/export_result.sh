#!/system/bin/sh
echo "=== Exporting Transformer Turns Ratio Results ==="

RESULT_FILE="/sdcard/transformer_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Collect File Stats
FILE_EXISTS=false
FILE_SIZE=0
FILE_MTIME=0
FILE_CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_CONTENT=$(cat "$RESULT_FILE")
fi

# 3. Get Task Start Time
TASK_START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 4. Check App State
# Check if app is in foreground
APP_FOCUSED=false
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_FOCUSED=true
fi

# 5. Generate JSON Report
# Note: creating JSON manually in shell since jq might not be available
echo "{" > "$JSON_OUTPUT"
echo "  \"timestamp\": $CURRENT_TIME," >> "$JSON_OUTPUT"
echo "  \"task_start_time\": $TASK_START_TIME," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"file_mtime\": $FILE_MTIME," >> "$JSON_OUTPUT"
echo "  \"app_focused\": $APP_FOCUSED," >> "$JSON_OUTPUT"
# Escape newlines for JSON string safely
CLEAN_CONTENT=$(echo "$FILE_CONTENT" | tr '\n' '\\n' | sed 's/"/\\"/g')
echo "  \"file_content\": \"$CLEAN_CONTENT\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"