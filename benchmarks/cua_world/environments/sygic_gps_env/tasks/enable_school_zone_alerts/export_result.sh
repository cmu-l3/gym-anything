#!/system/bin/sh
# Export script for enable_school_zone_alerts task
# Runs inside the Android environment

echo "=== Exporting results ==="

# 1. Capture final screenshot (CRITICAL for verification)
screencap -p /sdcard/task_final.png

# 2. Dump UI hierarchy (useful secondary signal if text is parsable)
uiautomator dump /sdcard/window_dump.xml 2>/dev/null || true

# 3. Create JSON result with timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pgrep -f "com.sygic.aura" > /dev/null && echo "true" || echo "false")
SCREENSHOT_EXISTS=$([ -f /sdcard/task_final.png ] && echo "true" || echo "false")

# Create JSON file
cat > /sdcard/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "screenshot_exists": $SCREENSHOT_EXISTS,
  "final_screenshot_path": "/sdcard/task_final.png",
  "ui_dump_path": "/sdcard/window_dump.xml"
}
EOF

echo "Result saved to /sdcard/task_result.json"