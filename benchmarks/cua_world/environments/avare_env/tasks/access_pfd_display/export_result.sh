#!/system/bin/sh
# Export script for access_pfd_display task
# Runs on Android device

echo "=== Exporting access_pfd_display results ==="

PACKAGE="com.ds.avare"
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Check if app is running
APP_RUNNING="false"
if pgrep -f "com.ds.avare" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Create result JSON
# Note: Android mksh echo does not support complex formatting easily, so we construct simply.
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result saved to /sdcard/task_result.json"
echo "=== Export Complete ==="