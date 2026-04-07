#!/system/bin/sh
echo "=== Exporting set_home_location results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final.png
echo "Final screenshot captured"

# Dump UI hierarchy to XML (useful for verifier to parse text)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null || echo "UI dump failed"

# Check if Sygic is running
APP_RUNNING=$(pgrep -f "com.sygic.aura" > /dev/null && echo "true" || echo "false")

# Create JSON result
# Note: On Android shell, we construct JSON manually
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_was_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Set permissions so host can read it
chmod 666 /sdcard/task_result.json 2>/dev/null || true
chmod 666 /sdcard/task_final.png 2>/dev/null || true
chmod 666 /sdcard/ui_dump.xml 2>/dev/null || true

echo "=== Export complete ==="