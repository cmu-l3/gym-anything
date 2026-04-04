#!/system/bin/sh
echo "=== Setting up CT Secondary Current Task ==="

# Define package and file paths
PACKAGE="com.hsn.electricalcalculations"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_FILE="/sdcard/ct_check.txt"

# Record start time
date +%s > "$START_TIME_FILE"

# Clean up previous artifacts
rm -f "$RESULT_FILE"
rm -f "/sdcard/task_result.json"
rm -f "/sdcard/task_final.png"

# Ensure screen is on and unlocked (basic check)
input keyevent 82 2>/dev/null

# Force stop the app to ensure clean state
am force-stop "$PACKAGE"
sleep 1

# Launch the application to the main activity
echo "Launching Electrical Calculations..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Dismiss potential ad/welcome screen by pressing Back once
input keyevent 4
sleep 1

# If we exited the app (because there was no ad), relaunch
if ! dumpsys window | grep -q "$PACKAGE"; then
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

echo "=== Setup Complete ==="