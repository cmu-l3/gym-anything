#!/system/bin/sh
echo "=== Setting up heater_power_derating task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up any previous results
rm -f /sdcard/Download/derated_power.txt 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

PACKAGE="com.hsn.electricalcalculations"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 1

# Press Home to ensure clean back stack
input keyevent KEYCODE_HOME
sleep 1

# Launch the application
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="