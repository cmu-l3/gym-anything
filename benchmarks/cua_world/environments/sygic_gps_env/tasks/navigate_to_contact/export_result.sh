#!/system/bin/sh
# Export script for navigate_to_contact task
# Runs on Android via ADB shell

echo "=== Exporting results ==="

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png
echo "Final screenshot saved to /sdcard/final_screenshot.png"

# 2. Capture UI hierarchy (as backup for VLM)
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# 3. Check if Sygic is running
APP_RUNNING="false"
if ps -A | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
fi

# 4. Get timestamps
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 5. Create result JSON
# Note: Android shell usually doesn't have jq, so we construct JSON manually
echo "{" > /sdcard/task_result.json
echo "  \"timestamp\": \"$(date)\"," >> /sdcard/task_result.json
echo "  \"task_start\": $START_TIME," >> /sdcard/task_result.json
echo "  \"task_end\": $END_TIME," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON saved to /sdcard/task_result.json"
echo "=== Export complete ==="