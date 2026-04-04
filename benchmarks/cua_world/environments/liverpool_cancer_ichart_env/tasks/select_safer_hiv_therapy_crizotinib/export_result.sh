#!/system/bin/sh
echo "=== Exporting Task Results ==="

RESULT_FILE="/sdcard/crizotinib_hiv_safety.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check Result File
FILE_EXISTS="false"
CONTENT_LINE_1=""
CONTENT_LINE_2=""
CONTENT_LINE_3=""
CONTENT_LINE_4=""
FILE_TIMESTAMP="0"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Read first 4 lines safely
    CONTENT_LINE_1=$(sed -n '1p' "$RESULT_FILE" | tr -d '\r\n')
    CONTENT_LINE_2=$(sed -n '2p' "$RESULT_FILE" | tr -d '\r\n')
    CONTENT_LINE_3=$(sed -n '3p' "$RESULT_FILE" | tr -d '\r\n')
    CONTENT_LINE_4=$(sed -n '4p' "$RESULT_FILE" | tr -d '\r\n')
    
    # Get timestamp (stat in Android mksh might differ, using ls -l behavior or date)
    FILE_TIMESTAMP=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
fi

# 3. Check Task Start Time
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 4. Construct JSON Output
# We construct JSON manually because `jq` is not guaranteed on Android
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"start_time\": $START_TIME," >> "$JSON_OUTPUT"
echo "  \"file_timestamp\": $FILE_TIMESTAMP," >> "$JSON_OUTPUT"
echo "  \"line1\": \"$CONTENT_LINE_1\"," >> "$JSON_OUTPUT"
echo "  \"line2\": \"$CONTENT_LINE_2\"," >> "$JSON_OUTPUT"
echo "  \"line3\": \"$CONTENT_LINE_3\"," >> "$JSON_OUTPUT"
echo "  \"line4\": \"$CONTENT_LINE_4\"," >> "$JSON_OUTPUT"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "JSON export created at $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export Complete ==="