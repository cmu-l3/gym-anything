#!/system/bin/sh
# Export script for enable_dark_theme task
# Checks system state and exports results to JSON

echo "=== Exporting Enable Dark Theme results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png
echo "Final screenshot saved to /sdcard/task_final.png"

# 2. Check System Dark Mode Setting
# Expected output: "Night mode: yes"
NIGHT_MODE_OUTPUT=$(cmd uimode night 2>&1)
echo "Night mode raw output: $NIGHT_MODE_OUTPUT"

if echo "$NIGHT_MODE_OUTPUT" | grep -q "Night mode: yes"; then
    IS_DARK_MODE="true"
else
    IS_DARK_MODE="false"
fi

# 3. Check Foreground App
PACKAGE="com.robert.fcView"
CURRENT_FOCUS=$(dumpsys window | grep -i "mCurrentFocus" | head -1)
echo "Final Focus: $CURRENT_FOCUS"

if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
else
    APP_IN_FOREGROUND="false"
fi

# 4. Check Timestamps (Anti-Gaming)
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 5. Create JSON Result
# Note: creating in /sdcard/task_result.json for verifier retrieval
cat > /sdcard/task_result.json <<EOF
{
  "is_dark_mode_enabled": $IS_DARK_MODE,
  "app_in_foreground": $APP_IN_FOREGROUND,
  "night_mode_raw": "$NIGHT_MODE_OUTPUT",
  "start_time": $START_TIME,
  "end_time": $END_TIME,
  "duration_seconds": $DURATION
}
EOF

echo "Result JSON created at /sdcard/task_result.json"
cat /sdcard/task_result.json

echo "=== Export complete ==="