#!/system/bin/sh
echo "=== Exporting LM317 Task Results ==="

RESULT_FILE="/sdcard/lm317_design.txt"
EXPORT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check Result File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME="0"
TASK_START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE")
    # Get file modification time (Android stat might differ, using ls -l as fallback or date)
    # Trying stat -c %Y first
    FILE_MOD_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null)
    
    if [ -z "$FILE_MOD_TIME" ]; then
        # Fallback if stat is missing/different on this android version
        FILE_MOD_TIME=$(date +%s) # Approximation: existing now implies created
    fi
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "com.hsn.electricalcalculations" >/dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# We construct JSON manually using echo to avoid dependency on jq
echo "{" > "$EXPORT_JSON"
echo "  \"timestamp\": $(date +%s)," >> "$EXPORT_JSON"
echo "  \"task_start\": $TASK_START_TIME," >> "$EXPORT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$EXPORT_JSON"
echo "  \"file_content\": \"$(echo "$FILE_CONTENT" | tr -d '\n' | sed 's/"/\\"/g'),\"" >> "$EXPORT_JSON"
echo "  \"file_mod_time\": $FILE_MOD_TIME," >> "$EXPORT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$EXPORT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$EXPORT_JSON"
echo "}" >> "$EXPORT_JSON"

echo "Result exported to $EXPORT_JSON"
cat "$EXPORT_JSON"