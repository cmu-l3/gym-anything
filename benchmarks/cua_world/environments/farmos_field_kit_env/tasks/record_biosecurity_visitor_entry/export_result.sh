#!/system/bin/sh
# Export script for record_biosecurity_visitor_entry task

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Captured final screenshot"

# 2. Dump UI Hierarchy (useful for text verification if VLM is ambiguous)
uiautomator dump /sdcard/ui_dump.xml
echo "Dumped UI hierarchy"

# 3. Create Result JSON
# We include timestamps to ensure the file was created during the task
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Simple JSON construction using echo
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $START_TIME," >> /sdcard/task_result.json
echo "  \"task_end\": $END_TIME," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON created at /sdcard/task_result.json"
echo "=== Export Complete ==="