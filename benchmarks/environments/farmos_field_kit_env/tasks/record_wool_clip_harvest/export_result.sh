#!/system/bin/sh
# Export script for record_wool_clip_harvest task
# Captures UI state and final screenshot for verification.

echo "=== Exporting task results ==="

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Dump UI hierarchy (XML)
# This allows us to textually verify what is on the screen (e.g. log list items)
uiautomator dump /sdcard/ui_dump.xml
echo "UI hierarchy dumped."

# 3. Record task end time
date +%s > /sdcard/task_end_time.txt

echo "=== Export complete ==="