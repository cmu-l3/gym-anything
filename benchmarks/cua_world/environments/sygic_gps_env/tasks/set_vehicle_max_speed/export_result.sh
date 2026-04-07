#!/system/bin/sh
# Export script for set_vehicle_max_speed task

echo "=== Exporting task results ==="

# Record end time
date +%s > /sdcard/task_end_time.txt

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Dump UI hierarchy (might capture the text "90 km/h" if it's a standard textview)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Create a JSON-like result file (using simple echo for Android shell compatibility)
# Note: Android shell usually doesn't have jq or complex json tools
echo "{" > /sdcard/task_result.json
echo "  \"task_completed\": true," >> /sdcard/task_result.json
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="