#!/system/bin/sh
# Export script for record_livestock_weighin_session
# Runs on Android device

echo "=== Exporting Results ==="

# Record end time
date +%s > /sdcard/task_end_time.txt

# Capture final high-res screenshot
screencap -p /sdcard/final_screenshot.png
echo "Final screenshot saved to /sdcard/final_screenshot.png"

# Dump UI hierarchy (useful for debugging or text extraction if VLM fails)
uiautomator dump /sdcard/ui_dump.xml
echo "UI dump saved to /sdcard/ui_dump.xml"

# Create a simple JSON result file with timestamp info
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(cat /sdcard/task_end_time.txt 2>/dev/null || echo "0")

# Note: Android shell might not have advanced JSON tools, keeping it simple text
# The verifier on host will create the full JSON result.
echo "{\"start\": $START_TIME, \"end\": $END_TIME}" > /sdcard/task_timing.json

echo "=== Export Complete ==="