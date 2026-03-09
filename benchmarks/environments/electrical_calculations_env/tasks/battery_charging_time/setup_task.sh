#!/system/bin/sh
# Setup for battery_charging_time task

echo "=== Setting up Battery Charging Time task ==="

# Create task directory
mkdir -p /sdcard/tasks/battery_charging_time
mkdir -p /sdcard/tasks

# Clean up previous artifacts
rm -f /sdcard/tasks/charge_time_result.txt
rm -f /sdcard/tasks/charge_time_screenshot.png
rm -f /sdcard/tasks/battery_charging_time/task_result.json

# Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/battery_charging_time/start_time.txt

PACKAGE="com.hsn.electricalcalculations"

# Force stop to get clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# Launch the app to its main screen
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Dismiss any ads or overlays by pressing Back once
input keyevent KEYCODE_BACK
sleep 1

# Relaunch to ensure we're on the main screen (sometimes back exits the app)
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# Take screenshot of initial state
screencap -p /sdcard/tasks/battery_charging_time/initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="