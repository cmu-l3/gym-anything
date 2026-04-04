#!/system/bin/sh
echo "=== Setting up Star-Delta Conversion Task ==="

# Define paths
TASK_DIR="/sdcard/tasks/star_delta_conversion"
PACKAGE="com.hsn.electricalcalculations"

# record start time
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch app to main activity
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Handle potential "Rate Us" or Ad popups by sending Back once
# (Wait a bit for them to appear)
sleep 3
input keyevent KEYCODE_BACK
sleep 1

# If we accidentally exited the app (because there was no popup), relaunch
if ! dumpsys window | grep -q "$PACKAGE"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="