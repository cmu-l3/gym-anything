#!/system/bin/sh
# Export script for check_airport_metar task

echo "=== Exporting check_airport_metar result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot (Crucial for VLM)
screencap -p /sdcard/final_screenshot.png
echo "Captured final screenshot"

# Check if Avare is currently running/focused
PACKAGE="com.ds.avare"
APP_RUNNING="false"
if ps -A | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# Attempt to dump UI hierarchy (as backup data, though Avare uses custom views often)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
UI_DUMP_EXISTS="false"
if [ -f /sdcard/ui_dump.xml ]; then
    UI_DUMP_EXISTS="true"
fi

# Create JSON result
# Note: Using a temporary file approach isn't strictly necessary in Android shell 
# if we just echo to the file, but we'll follow good practice.
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "final_screenshot_path": "/sdcard/final_screenshot.png"
}
EOF

chmod 666 /sdcard/task_result.json 2>/dev/null

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="