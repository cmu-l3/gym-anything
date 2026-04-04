#!/system/bin/sh
# Setup script for electricity_cost_calc task
set -e
echo "=== Setting up Electricity Cost Calculation task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.hsn.electricalcalculations"

# Force stop app to ensure clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# Remove any previous result screenshot
rm -f /sdcard/task_result.png 2>/dev/null || true

# Clear app data for clean state (no cached inputs from previous tasks)
pm clear $PACKAGE 2>/dev/null || true
sleep 1

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch app for initialization
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss any ad/promo overlay by pressing back
input keyevent KEYCODE_BACK
sleep 2

# Ensure we are back in the app or relaunch if Back exited it
if ! dumpsys window windows | grep -q "mCurrentFocus.*$PACKAGE"; then
    echo "Relaunching app..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial state screenshot for evidence
screencap -p /sdcard/task_initial_state.png

echo "=== Electricity Cost Calculation task setup complete ==="