#!/system/bin/sh
# Export script for electricity_cost_calc task
echo "=== Exporting Electricity Cost Calculation results ==="

PACKAGE="com.hsn.electricalcalculations"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 1. Check if the user saved the requested screenshot
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_VALID="false"

if [ -f /sdcard/task_result.png ]; then
    USER_SCREENSHOT_EXISTS="true"
    # Check timestamp to ensure it was created DURING the task
    FILE_TIME=$(stat -c %Y /sdcard/task_result.png 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        USER_SCREENSHOT_VALID="true"
    fi
fi

# 2. Check if the app is currently running in foreground
APP_IN_FOREGROUND="false"
CURRENT_FOCUS=$(dumpsys window windows 2>/dev/null | grep -i "mCurrentFocus" | head -1)
if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
fi

# 3. Capture the final state (fallback/verification evidence)
screencap -p /sdcard/task_final_state.png

# 4. Dump UI hierarchy (optional helper for debugging)
uiautomator dump /sdcard/task_ui_dump.xml 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON="/sdcard/task_result_temp.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_time": $NOW,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_valid_timestamp": $USER_SCREENSHOT_VALID,
    "app_in_foreground": $APP_IN_FOREGROUND,
    "final_screenshot_path": "/sdcard/task_final_state.png",
    "user_screenshot_path": "/sdcard/task_result.png"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="