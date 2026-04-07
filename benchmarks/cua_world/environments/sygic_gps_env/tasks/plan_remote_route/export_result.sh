#!/system/bin/sh
# Export script for plan_remote_route task.
# Runs inside the Android environment.

echo "=== Exporting plan_remote_route results ==="

# 1. Capture final screenshot (CRITICAL for VLM)
screencap -p /sdcard/task_final.png
echo "Final screenshot saved to /sdcard/task_final.png"

# 2. Dump UI hierarchy (CRITICAL for programmatic verification)
uiautomator dump /sdcard/ui_dump.xml
echo "UI hierarchy dumped to /sdcard/ui_dump.xml"

# 3. Check if app is running
PID=$(pidof com.sygic.aura)
APP_RUNNING="false"
if [ -n "$PID" ]; then
    APP_RUNNING="true"
fi

# 4. Create result JSON
# Note: Android shell (mksh) JSON creation
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "{
  \"task_start\": $TASK_START,
  \"task_end\": $TASK_END,
  \"app_running\": $APP_RUNNING,
  \"screenshot_path\": \"/sdcard/task_final.png\",
  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"
}" > /sdcard/task_result.json

echo "Result JSON saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="