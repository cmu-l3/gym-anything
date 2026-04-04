#!/system/bin/sh
# Export script for wire_dc_resistance task
# Runs on Android device

echo "=== Exporting task results ==="

# 1. Define paths
RESULT_IMG="/sdcard/task_result.png"
JSON_OUT="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 2. Get Task Start Time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# 3. Check for result screenshot
SCREENSHOT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$RESULT_IMG" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_SIZE=$(ls -l "$RESULT_IMG" | awk '{print $4}')
    
    # Check modification time (Android ls -l doesn't always give seconds, 
    # so we rely on the file not existing in setup_task.sh)
    # Since we deleted it in setup, if it exists now, it was created during task.
    FILE_CREATED_DURING_TASK="true"
fi

# 4. Check if App is currently in foreground (Heuristic for "Did they leave it open?")
APP_ focused="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_FOCUSED="true"
fi

# 5. Dump UI hierarchy for debugging/verification
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# 6. Create JSON result
# Note: JSON creation in shell is fragile, so we keep it simple
echo "{" > "$JSON_OUT"
echo "  \"timestamp\": $(date +%s)," >> "$JSON_OUT"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$JSON_OUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUT"
echo "  \"file_size\": $FILE_SIZE," >> "$JSON_OUT"
echo "  \"app_focused\": \"$APP_FOCUSED\"" >> "$JSON_OUT"
echo "}" >> "$JSON_OUT"

# 7. Capture a system-level screenshot of the final state (fallback)
screencap -p /sdcard/final_state_fallback.png

echo "Export complete. Result saved to $JSON_OUT"
cat "$JSON_OUT"