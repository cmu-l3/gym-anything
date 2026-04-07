#!/system/bin/sh
# Export script for change_app_interface_language task
# Runs on Android device

echo "=== Exporting task results ==="

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

# 2. Check if App is still running
APP_RUNNING="false"
if ps -A | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
fi

# 3. Capture Final Screenshot (CRITICAL for VLM verification)
screencap -p /sdcard/task_final.png

# 4. Check if screenshots differ (Anti-gaming "do nothing" check)
# Simple size comparison
INIT_SIZE=$(stat -c %s /sdcard/task_initial.png 2>/dev/null || echo "0")
FINAL_SIZE=$(stat -c %s /sdcard/task_final.png 2>/dev/null || echo "0")
SCREENSHOTS_DIFFER="false"
if [ "$INIT_SIZE" != "$FINAL_SIZE" ]; then
    SCREENSHOTS_DIFFER="true"
fi

# 5. Create JSON result
# Note: Android shell usually doesn't have jq, so we construct JSON manually
RESULT_JSON="/sdcard/task_result.json"

echo "{" > $RESULT_JSON
echo "  \"task_duration_sec\": $DURATION," >> $RESULT_JSON
echo "  \"app_was_running\": $APP_RUNNING," >> $RESULT_JSON
echo "  \"screenshots_differ\": $SCREENSHOTS_DIFFER," >> $RESULT_JSON
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"," >> $RESULT_JSON
echo "  \"initial_screenshot_path\": \"/sdcard/task_initial.png\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

# 6. Permissions (ensure host can read it)
chmod 666 $RESULT_JSON 2>/dev/null
chmod 666 /sdcard/task_final.png 2>/dev/null

echo "Result exported to $RESULT_JSON"
echo "=== Export complete ==="