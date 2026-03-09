#!/system/bin/sh
echo "=== Exporting Mushroom Log Task Results ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (useful for debugging or programmatic checks if VLM fails)
uiautomator dump /sdcard/ui_dump.xml

# 3. Timestamp Check
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. App State Check
APP_RUNNING="false"
if pgrep -f "org.farmos.app" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
# Note: Android shell usually has limited JSON tools, so we manually construct it.
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"
echo "=== Export Complete ==="