#!/system/bin/sh
# Export script for compare_anticoagulant_strategies_rcc
# Runs inside Android environment

echo "=== Exporting Task Results ==="

OUTPUT_FILE="/sdcard/rcc_anticoagulant_matrix.txt"
RESULT_JSON="/sdcard/task_result.json"
SCREENSHOT="/sdcard/task_final.png"

# 1. Take final screenshot
screencap -p "$SCREENSHOT" 2>/dev/null
echo "Screenshot saved to $SCREENSHOT"

# 2. Check output file
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}') 2>/dev/null
    if [ -z "$FILE_SIZE" ]; then FILE_SIZE="0"; fi
fi

# 3. Check if app is running (in foreground)
# simple check if package is in window dump
DUMPSYS=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp')
if echo "$DUMPSYS" | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Create JSON payload
# Note: JSON creation in raw sh is tricky, using simple string construction
# Escaping newlines in content for JSON safety
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')

echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "JSON result created at $RESULT_JSON"
cat "$RESULT_JSON"