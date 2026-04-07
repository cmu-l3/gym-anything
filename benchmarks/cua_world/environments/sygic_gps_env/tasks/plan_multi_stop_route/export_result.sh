#!/system/bin/sh
# export_result.sh - Capture final state and logs
set -e
echo "=== Exporting plan_multi_stop_route results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null || true

# 2. Dump UI hierarchy (for programmatic verification of text)
uiautomator dump /sdcard/task_ui_dump.xml 2>/dev/null || true

# 3. Check if app is running
APP_RUNNING="false"
if dumpsys activity activities | grep -i "mResumedActivity" | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
fi

# 4. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 5. Create result JSON
# Note: Android shell is limited, constructing JSON manually
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"ui_dump_exists\": $([ -f /sdcard/task_ui_dump.xml ] && echo "true" || echo "false")," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final_state.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# 6. Set permissions so host can read
chmod 666 /sdcard/task_result.json 2>/dev/null || true
chmod 666 /sdcard/task_ui_dump.xml 2>/dev/null || true
chmod 666 /sdcard/task_final_state.png 2>/dev/null || true

echo "=== Export complete ==="