#!/system/bin/sh
set -e
echo "=== Setting up op_amp_noninverting_gain task ==="

# Ensure tasks directory exists
mkdir -p /sdcard/tasks

# Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/task_start_time.txt

# Clean any previous task artifacts
rm -f /sdcard/tasks/op_amp_results.txt
rm -f /sdcard/tasks/op_amp_result.png
rm -f /sdcard/tasks/task_export.json

PACKAGE="com.hsn.electricalcalculations"

# Force stop to get a clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Launch the app to its main screen
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Dismiss any initial ad/promo overlay that might appear on cold boot
# Press Back once
input keyevent KEYCODE_BACK
sleep 2

# If we accidentally exited the app, relaunch
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

# Capture initial state screenshot
screencap -p /sdcard/tasks/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="