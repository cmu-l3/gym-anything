#!/system/bin/sh
echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/tasks/final_state.png

# 2. Dump UI Hierarchy (useful for debugging or layout verification)
uiautomator dump /sdcard/tasks/final_ui.xml 2>/dev/null

# 3. Save simple result metadata
# We can't easily check internal app state without root/adb deeper access, 
# so we rely on the screenshot for the verifier.
date +%s > /sdcard/tasks/task_end_time.txt

# Create a basic JSON result file
cat > /sdcard/tasks/task_result.json <<EOF
{
  "timestamp": "$(date)",
  "final_screenshot_path": "/sdcard/tasks/final_state.png",
  "ui_dump_path": "/sdcard/tasks/final_ui.xml"
}
EOF

echo "Result exported to /sdcard/tasks/task_result.json"