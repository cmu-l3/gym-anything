#!/system/bin/sh
# Setup script for pt_primary_voltage task

echo "=== Setting up PT Primary Voltage Task ==="

PACKAGE="com.hsn.electricalcalculations"
TASK_DIR="/sdcard/tasks/pt_primary_voltage"

# Create task directory if it doesn't exist (though strictly it's read-only mount, we might need writeable space)
# We will write temp files to /sdcard/ which is writeable
mkdir -p /sdcard/tmp

# 1. Clean up previous artifacts
rm -f /sdcard/pt_result.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/pt_final_screenshot.png

# 2. Record task start time
date +%s > /sdcard/task_start_time.txt

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch app
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# 7. Take initial screenshot for evidence
screencap -p /sdcard/pt_initial_screenshot.png

echo "=== Setup Complete ==="