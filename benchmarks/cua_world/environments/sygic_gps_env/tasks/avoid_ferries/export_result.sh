#!/system/bin/sh
# Export script for avoid_ferries task
# Runs on Android device/emulator

echo "=== Exporting results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI hierarchy (useful for text validation)
# This creates an XML file describing the current screen layout/text
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# 3. Record task end time
date +%s > /sdcard/task_end_time.txt

# 4. Create a JSON result file
# Note: JSON creation in raw shell is tricky, keeping it simple
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(cat /sdcard/task_end_time.txt 2>/dev/null || echo "0")

echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $START_TIME," >> /sdcard/task_result.json
echo "  \"task_end\": $END_TIME," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"
echo "=== Export complete ==="