#!/system/bin/sh
# Setup script for series_capacitance task

echo "=== Setting up Series Capacitance task ==="

# Define package
PACKAGE="com.hsn.electricalcalculations"

# 1. Force stop the app to ensure a clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# 2. Go to Home Screen to ensure neutral starting point
input keyevent KEYCODE_HOME
sleep 2

# 3. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 4. Launch the app using robust helper
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# 5. Take initial screenshot (should be home screen)
screencap -p /sdcard/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="