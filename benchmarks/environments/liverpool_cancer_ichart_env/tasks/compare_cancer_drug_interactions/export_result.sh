#!/system/bin/sh
# Export script for compare_cancer_drug_interactions task

echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
screencap -p /sdcard/task_final.png 2>/dev/null
echo "Final screenshot captured"

# Check if the app is currently in the foreground (did it crash? did agent close it?)
PACKAGE="com.liverpooluni.ichartoncology"
APP_RUNNING=false
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_RUNNING=true
fi

# Create result JSON
# We use a temp file and move it to avoid partial writes
TEMP_JSON="/sdcard/temp_result.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/sdcard/task_final.png",
    "initial_screenshot_path": "/sdcard/task_initial.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"
echo "=== Export complete ==="