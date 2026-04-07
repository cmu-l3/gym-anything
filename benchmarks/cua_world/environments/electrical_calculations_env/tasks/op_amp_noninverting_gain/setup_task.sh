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
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Capture initial state screenshot
screencap -p /sdcard/tasks/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="