#!/system/bin/sh
# Export script for check_antibiotic_interaction_with_venetoclax
# Runs on Android device

echo "=== Exporting task results ==="

TASK_DIR="/sdcard/tasks/check_antibiotic_interaction_with_venetoclax"
RESULT_FILE="$TASK_DIR/result.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check Result File
FILE_EXISTS=false
FILE_CONTENT=""
FILE_MODIFIED_TIME=0

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS=true
    FILE_CONTENT=$(cat "$RESULT_FILE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    
    # Get timestamp if possible (stat might not be available on all android shells)
    # using ls -l as fallback
    FILE_MODIFIED_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
fi

# 3. Check if App is in foreground
APP_VISIBLE=false
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE=true
fi

# 4. Dump UI hierarchy (useful for debugging/verification)
uiautomator dump /sdcard/window_dump.xml 2>/dev/null || true

# 5. Create JSON Output
# JSON creation in pure shell is tricky, doing simple string concatenation
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"app_visible\": $APP_VISIBLE," >> "$JSON_OUTPUT"
echo "  \"timestamp\": \"$(date)\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

cat "$JSON_OUTPUT"
echo "=== Export complete ==="