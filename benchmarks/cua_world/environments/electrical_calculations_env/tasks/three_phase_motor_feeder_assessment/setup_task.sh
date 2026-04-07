#!/system/bin/sh
# Setup script for Three-Phase Motor Feeder Assessment task

echo "=== Setting up Three-Phase Motor Feeder Assessment ==="

# Force-stop the app for a clean state
am force-stop com.hsn.electricalcalculations
sleep 1

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Clean up any stale outputs from previous runs
rm -f /sdcard/final_screenshot_motor_feeder.png 2>/dev/null || true
rm -f /sdcard/ui_dump_motor_feeder.xml 2>/dev/null || true
rm -f /sdcard/ui_dump.xml 2>/dev/null || true

# Record task start timestamp (AFTER cleaning stale outputs)
date +%s > /sdcard/task_start_ts_motor_feeder.txt

# Launch the app
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc
if [ -z "$CURRENT" ]; then
    echo "App not in foreground, relaunching..."
    sleep 5
fi

echo "=== Setup Complete: Navigate to the 3-Phase, CT, and Cable calculators ==="
