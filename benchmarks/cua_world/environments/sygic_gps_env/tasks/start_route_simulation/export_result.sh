#!/system/bin/sh
# Export script for start_route_simulation
# Runs on Android device via adb shell

echo "=== Exporting results ==="

PACKAGE="com.sygic.aura"
RESULT_FILE="/sdcard/task_result.json"
SCREENSHOT_FILE="/sdcard/task_final.png"

# 1. Capture Final Screenshot
screencap -p "$SCREENSHOT_FILE"
echo "Screenshot saved to $SCREENSHOT_FILE"

# 2. Collect State Information

# Task Timings
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# App Running Status
# Check if package is in the top focused window
CURRENT_FOCUS=$(dumpsys window windows 2>/dev/null | grep -i "mCurrentFocus")
if echo "$CURRENT_FOCUS" | grep -qi "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
else
    APP_IN_FOREGROUND="false"
fi

# Activity Name (helps detect if we are in navigation mode)
# Helper to get the resumed activity component name
RESUMED_ACTIVITY=$(dumpsys activity activities 2>/dev/null | grep -i "mResumedActivity" | grep "$PACKAGE" | tail -n 1)

# Clean up strings for JSON
CLEAN_FOCUS=$(echo "$CURRENT_FOCUS" | sed 's/"//g' | xargs)
CLEAN_ACTIVITY=$(echo "$RESUMED_ACTIVITY" | sed 's/"//g' | xargs)

# 3. Write Result JSON
# Note: creating JSON in shell is manual
echo "{" > "$RESULT_FILE"
echo "  \"task_start\": $TASK_START," >> "$RESULT_FILE"
echo "  \"task_end\": $TASK_END," >> "$RESULT_FILE"
echo "  \"app_in_foreground\": $APP_IN_FOREGROUND," >> "$RESULT_FILE"
echo "  \"current_focus\": \"$CLEAN_FOCUS\"," >> "$RESULT_FILE"
echo "  \"resumed_activity\": \"$CLEAN_ACTIVITY\"," >> "$RESULT_FILE"
echo "  \"screenshot_path\": \"$SCREENSHOT_FILE\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

echo "Result JSON written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="