#!/system/bin/sh
# Export script for check_immunosuppressant_with_bosutinib task

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
screencap -p /sdcard/final_screenshot.png
if [ -f /sdcard/final_screenshot.png ]; then
    SCREENSHOT_EXISTS="true"
else
    SCREENSHOT_EXISTS="false"
fi

# 2. Check if App is still running/focused
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# 3. Create JSON result
# We construct JSON manually using echo since jq might not be available on all Android envs
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Set permissions to ensure host can read it
chmod 666 /sdcard/task_result.json 2>/dev/null
chmod 666 /sdcard/final_screenshot.png 2>/dev/null

echo "Result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="