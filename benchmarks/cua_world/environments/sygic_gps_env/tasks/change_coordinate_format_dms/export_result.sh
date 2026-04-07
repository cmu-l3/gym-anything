#!/system/bin/sh
# Export script for change_coordinate_format_dms task
# Runs inside the Android environment

echo "=== Exporting results ==="

# 1. Capture final screenshot (CRITICAL for verification)
screencap -p /sdcard/task_final.png
echo "Final screenshot saved to /sdcard/task_final.png"

# 2. Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check if app is in foreground (basic check)
APP_FOCUSED=$(dumpsys window | grep mCurrentFocus | grep "com.sygic.aura" && echo "true" || echo "false")

# 4. Create JSON result
# Note: We use simple echo construction to avoid dependency on jq which might not be in Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_focused\": $APP_FOCUSED," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="