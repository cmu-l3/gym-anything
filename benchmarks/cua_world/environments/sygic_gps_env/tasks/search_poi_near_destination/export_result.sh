#!/system/bin/sh
# Export script for search_poi_near_destination task
# Runs on Android device/emulator

echo "=== Exporting search_poi_near_destination results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI hierarchy (for text verification)
uiautomator dump /sdcard/ui_dump.xml > /dev/null 2>&1

# 3. Record end time and app state
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pidof com.sygic.aura > /dev/null && echo "true" || echo "false")

# 4. Create result JSON
# Note: Android shell usually lacks complex JSON tools, using echo
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="