#!/system/bin/sh
# Export script for ALK Inhibitor Audit Task
# Runs inside Android environment

echo "=== Exporting Results ==="

RESULT_FILE="/sdcard/alk_transplant_audit.txt"
JSON_OUTPUT="/sdcard/task_result.json"
SCREENSHOT="/sdcard/final_screenshot.png"

# 1. Take final screenshot
screencap -p "$SCREENSHOT" 2>/dev/null

# 2. Check Result File
FILE_EXISTS="false"
FILE_SIZE="0"
CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$RESULT_FILE" | awk '{print $4}')
    # Read content safely (escape quotes for JSON)
    CONTENT=$(cat "$RESULT_FILE" | sed 's/"/\\"/g' | tr '\n' '|')
fi

# 3. Check App State
APP_RUNNING="false"
if ps -A | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# We construct JSON manually since jq might not be on the device
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUTPUT"
echo "  \"app_running\": $APP_RUNNING," >> "$JSON_OUTPUT"
echo "  \"content_raw\": \"$CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"timestamp\": \"$(date)\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"