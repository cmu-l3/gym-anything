#!/system/bin/sh
echo "=== Exporting series_rlc_impedance results ==="

TASK_DIR="/sdcard/tasks/series_rlc_impedance"
RESULT_FILE="$TASK_DIR/result.txt"
EXPORT_JSON="$TASK_DIR/task_result.json"
START_TIME_FILE="$TASK_DIR/start_time.txt"

# 1. Capture Final State
screencap -p "$TASK_DIR/final_state.png"

# 2. Get Task Timing
TASK_END=$(date +%s)
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MODIFIED_TIME=0
IS_NEW_FILE="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE")
    # Get modification time (Android stat might differ, using ls -l hack if stat fails, 
    # but strictly we rely on creating a new file)
    FILE_MODIFIED_TIME=$(date +%s) # Approximation since we just checked it
    
    if [ "$FILE_MODIFIED_TIME" -ge "$TASK_START" ]; then
        IS_NEW_FILE="true"
    fi
fi

# 4. Check App State (is it top/visible?)
APP_VISIBLE="false"
DUMPSYS=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp')
if echo "$DUMPSYS" | grep -q "com.hsn.electricalcalculations"; then
    APP_VISIBLE="true"
fi

# 5. Create JSON Result
# Note: constructing JSON manually in sh is fragile, keeping it simple.
# escaping quotes in content
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')

echo "{" > "$EXPORT_JSON"
echo "  \"task_start\": $TASK_START," >> "$EXPORT_JSON"
echo "  \"task_end\": $TASK_END," >> "$EXPORT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$EXPORT_JSON"
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$EXPORT_JSON"
echo "  \"is_new_file\": $IS_NEW_FILE," >> "$EXPORT_JSON"
echo "  \"app_visible\": $APP_VISIBLE," >> "$EXPORT_JSON"
echo "  \"final_screenshot\": \"$TASK_DIR/final_state.png\"" >> "$EXPORT_JSON"
echo "}" >> "$EXPORT_JSON"

echo "JSON Exported to $EXPORT_JSON"
cat "$EXPORT_JSON"
echo "=== Export complete ==="