#!/system/bin/sh
# Setup script for rms_to_peak_voltage task

echo "=== Setting up RMS to Peak Voltage Task ==="

# Create task directory
mkdir -p /sdcard/tasks/rms_to_peak_voltage
chmod 777 /sdcard/tasks/rms_to_peak_voltage

# Clean up previous artifacts
rm -f /sdcard/tasks/rms_to_peak_result.png
rm -f /sdcard/tasks/peak_voltage.txt
rm -f /sdcard/tasks/task_result.json

# Record start time
date +%s > /sdcard/tasks/rms_to_peak_voltage/start_time.txt

# Package name
PACKAGE="com.hsn.electricalcalculations"

# Force stop to ensure clean state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# Launch the app
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# Take initial screenshot for debug
screencap -p /sdcard/tasks/rms_to_peak_voltage/initial_state.png

echo "=== Setup Complete ==="