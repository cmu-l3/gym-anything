#!/system/bin/sh
set -e
echo "=== Setting up 555 Timer Astable task ==="

# Record task start time (for anti-gaming verification)
date +%s > /sdcard/task_start_time.txt

# Remove any previous results file
rm -f /sdcard/555_timer_results.txt

PACKAGE="com.hsn.electricalcalculations"

# Force stop the app for clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# Ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

# Verify app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Electrical Calculations app is not installed!"
    exit 1
fi

# Launch the app using robust helper
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== 555 Timer Astable task setup complete ==="