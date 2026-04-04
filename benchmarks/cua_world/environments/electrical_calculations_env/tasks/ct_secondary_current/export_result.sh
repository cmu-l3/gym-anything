#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Paths
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_FILE="/sdcard/ct_check.txt"
JSON_OUTPUT="/sdcard/task_result.json"
SCREENSHOT_PATH="/sdcard/task_final.png"

# Capture final state screenshot
screencap -p "$SCREENSHOT_PATH"

# Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# Check Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time (stat -c %Y is standard, but Android toybox/busybox might vary)
    # Using ls -l to get time might be parsing-heavy, trying stat first
    FILE_MOD_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null)
    
    # Fallback if stat fails
    if [ -z "$FILE_MOD_TIME" ]; then
        FILE_MOD_TIME=$(date +%s) # Assume now if we can't read it, verifier handles robustly
    fi
    
    if [ "$FILE_MOD_TIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if App is on top
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_VISIBLE="true"
fi

# construct JSON manually since jq might not be on Android
echo "{" > "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"app_visible\": $APP_VISIBLE," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"screenshot_path\": \"$SCREENSHOT_PATH\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export completed to $JSON_OUTPUT"
cat "$JSON_OUTPUT"