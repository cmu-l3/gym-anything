#!/system/bin/sh
# Export script for assess_diarrhea_management_safety_lapatinib
# Runs inside the Android environment

echo "=== Exporting Task Results ==="

OUTPUT_FILE="/sdcard/Download/lapatinib_supportive_care_report.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Screenshot captured."

# 2. Check File Existence and Metadata
FILE_EXISTS="false"
FILE_SIZE="0"
CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}' 2>/dev/null)
    # Read content (cat is safe for small text files)
    CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null)
fi

# 3. Check App State (is it still running?)
APP_RUNNING="false"
PROCESS=$(ps -A | grep "com.liverpooluni.ichartoncology")
if [ -n "$PROCESS" ]; then
    APP_RUNNING="true"
fi

# 4. Construct JSON Result
# Note: JSON construction in sh is fragile, manual formatting carefully
# Escape quotes in content
SAFE_CONTENT=$(echo "$CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_size\": \"$FILE_SIZE\"," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="