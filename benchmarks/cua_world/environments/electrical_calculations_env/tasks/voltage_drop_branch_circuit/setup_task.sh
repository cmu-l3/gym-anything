#!/system/bin/sh
set -e
echo "=== Setting up Voltage Drop Branch Circuit task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Remove any previous result file to ensure a clean state
rm -f /sdcard/voltage_drop_result.txt
rm -f /sdcard/task_result.json

# Force-stop the app to ensure we start fresh
am force-stop com.hsn.electricalcalculations
sleep 1

# Press Home to ensure we're at the home screen
input keyevent KEYCODE_HOME
sleep 2

# Verify app is installed
if ! pm list packages | grep -q "com.hsn.electricalcalculations"; then
    echo "ERROR: Electrical Calculations app not installed!"
    exit 1
fi

# Launch the app using robust helper
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Voltage Drop task setup complete ==="