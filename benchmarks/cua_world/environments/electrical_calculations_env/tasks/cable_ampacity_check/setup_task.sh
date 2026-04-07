#!/system/bin/sh
echo "=== Setting up cable_ampacity_check task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up any previous results
rm -f /sdcard/ampacity_result.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

PACKAGE="com.hsn.electricalcalculations"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Press Home to ensure we start from a neutral place
input keyevent KEYCODE_HOME
sleep 1

# Launch the application
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Capture initial state screenshot
screencap -p /sdcard/initial_screenshot.png

echo "=== Task setup complete ==="