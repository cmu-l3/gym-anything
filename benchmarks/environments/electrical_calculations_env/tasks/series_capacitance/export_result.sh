#!/system/bin/sh
# Export script for series_capacitance task

echo "=== Exporting Series Capacitance results ==="

# 1. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot (Crucial for VLM)
screencap -p /sdcard/task_final.png 2>/dev/null || true

# 3. Check if App is in Foreground
# We dump the window info and grep for the package name in the focused window
APP_FOCUSED="false"
if dumpsys window | grep -i "mCurrentFocus" | grep -q "com.hsn.electricalcalculations"; then
    APP_FOCUSED="true"
fi

# 4. Dump UI Hierarchy (Secondary evidence, optional but useful)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null || true

# 5. Create Result JSON
# We use a temp file and move it to avoid partial writes
TEMP_JSON="/sdcard/temp_result.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_focused": $APP_FOCUSED,
    "screenshot_path": "/sdcard/task_final.png",
    "ui_dump_path": "/sdcard/ui_dump.xml"
}
EOF

mv "$TEMP_JSON" /sdcard/task_result.json

echo "=== Export complete ==="