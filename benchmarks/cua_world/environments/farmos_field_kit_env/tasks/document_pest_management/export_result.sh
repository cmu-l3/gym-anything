#!/system/bin/sh
echo "=== Exporting document_pest_management results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Dump UI hierarchy to check for visible logs in the list
uiautomator dump /sdcard/ui_dump.xml > /dev/null 2>&1

# Check if app is still running
APP_RUNNING="false"
if pidof org.farmos.app > /dev/null; then
    APP_RUNNING="true"
fi

# Create a simple JSON result file
# Note: Complex JSON creation with sh on Android is tricky, keep it simple
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Set permissions to ensure it can be read
chmod 666 /sdcard/task_result.json
chmod 666 /sdcard/task_final.png
chmod 666 /sdcard/ui_dump.xml 2>/dev/null || true

echo "=== Export complete ==="
cat /sdcard/task_result.json