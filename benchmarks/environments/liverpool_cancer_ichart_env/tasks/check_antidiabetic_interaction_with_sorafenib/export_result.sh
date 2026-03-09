#!/system/bin/sh
# Export script for check_antidiabetic_interaction_with_sorafenib
# Runs inside Android environment

echo "=== Exporting Task Results ==="

RESULT_PATH="/sdcard/interaction_result.txt"
JSON_PATH="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png

# 2. Check Result File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$RESULT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_PATH")
    FILE_SIZE=$(stat -c %s "$RESULT_PATH" 2>/dev/null || wc -c < "$RESULT_PATH")
    
    # Check modification time against start time
    # Note: Android shell usually has limited stat/date, using -newer check if possible
    if [ -f /sdcard/task_start_ref_file ]; then
        if [ "$RESULT_PATH" -nt /sdcard/task_start_ref_file ]; then
            FILE_MODIFIED_DURING_TASK="true"
        fi
    elif [ -f /sdcard/task_start_time.txt ]; then
        START_TIME=$(cat /sdcard/task_start_time.txt)
        FILE_TIME=$(stat -c %Y "$RESULT_PATH" 2>/dev/null || echo "0")
        if [ "$FILE_TIME" -gt "$START_TIME" ]; then
            FILE_MODIFIED_DURING_TASK="true"
        fi
    else
        # Fallback: assume true if we can't verify timestamp in restricted shell
        FILE_MODIFIED_DURING_TASK="unknown"
    fi
fi

# 3. Check App State (is it in foreground?)
PACKAGE="com.liverpooluni.ichartoncology"
APP_IN_FOREGROUND="false"
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
fi

# 4. JSON Generation (Manual string construction for Android shell compatibility)
# Escape quotes in content
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{
  \"file_exists\": $FILE_EXISTS,
  \"file_created_during_task\": \"$FILE_MODIFIED_DURING_TASK\",
  \"file_size\": $FILE_SIZE,
  \"file_content\": \"$SAFE_CONTENT\",
  \"app_in_foreground\": $APP_IN_FOREGROUND,
  \"timestamp\": \"$(date)\"
}" > "$JSON_PATH"

echo "Export complete. Result saved to $JSON_PATH"
cat "$JSON_PATH"