#!/system/bin/sh
# Export script for navigate_to_airport_parking
# Runs inside Android environment

echo "=== Exporting Results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (for text verification)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# 3. Check if Sygic is running
if pidof com.sygic.aura > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Get timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create JSON result
# Note: We construct JSON manually as 'jq' might not be on the android device
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"