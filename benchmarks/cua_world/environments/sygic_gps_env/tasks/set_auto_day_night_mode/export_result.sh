#!/system/bin/sh
echo "=== Exporting set_auto_day_night_mode result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if App is still running
PACKAGE="com.sygic.aura"
APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Capture Final Screenshot
screencap -p /sdcard/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f "/sdcard/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 3. Create Result JSON
# We use a temp file and move it to avoid partial writes being read
TEMP_JSON="/sdcard/result_temp.json"
RESULT_JSON="/sdcard/task_result.json"

echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$TEMP_JSON"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$TEMP_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="