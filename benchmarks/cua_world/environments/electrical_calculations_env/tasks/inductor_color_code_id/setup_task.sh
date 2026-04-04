#!/system/bin/sh
echo "=== Setting up Inductor Color Code Task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up previous results
rm -f /sdcard/inductor_id.txt
rm -f /sdcard/task_result.json

PACKAGE="com.hsn.electricalcalculations"

# Ensure clean state by force stopping
am force-stop $PACKAGE
sleep 2

# Press Home to ensure we start from a neutral place
input keyevent KEYCODE_HOME
sleep 1

# Launch the application
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss any potential full-screen ads or "Rate Us" dialogs
input keyevent KEYCODE_BACK
sleep 1

# Ensure we are at the main menu (if back button exited the app, relaunch)
# Check if we are still in the app
if ! dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "Relaunching app..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="