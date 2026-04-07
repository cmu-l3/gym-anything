#!/system/bin/sh
# Export script for add_gas_stop_on_route
# Runs on Android device

echo "=== Exporting results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved."

# 2. Dump UI Hierarchy (XML)
uiautomator dump /sdcard/ui_dump.xml
echo "UI hierarchy dumped."

# 3. Create JSON Result
# Android shell has limited JSON tools, constructing manually
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pidof com.sygic.aura > /dev/null && echo "true" || echo "false")

echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"," >> /sdcard/task_result.json
echo "  \"xml_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "JSON result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json