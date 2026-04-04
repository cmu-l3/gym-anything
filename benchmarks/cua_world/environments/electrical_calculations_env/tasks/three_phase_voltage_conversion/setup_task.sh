#!/system/bin/sh
echo "=== Setting up Three-Phase Voltage Conversion Task ==="

# Define paths
TASK_DIR="/sdcard/tasks/three_phase_voltage_conversion"
START_TIME_FILE="$TASK_DIR/task_start_time.txt"
PACKAGE="com.hsn.electricalcalculations"

# Create task directory if it doesn't exist (though it should be mounted ro, 
# we might need a writable tmp dir for flags if the mount is ro. 
# Based on env config, /sdcard/tasks is ro. We must use /sdcard/ for writable files.)
# We will use /sdcard/tmp/three_phase for writable artifacts.
WRITABLE_DIR="/sdcard/tmp/three_phase"
mkdir -p "$WRITABLE_DIR"

# Record start time
date +%s > "$WRITABLE_DIR/task_start_time.txt"

# Clean up previous artifacts
rm -f "$WRITABLE_DIR/result.json"
rm -f "/sdcard/tasks/three_phase_voltage_conversion_result.png" # In case it was left over (though read-only mount prevents this, good for writable paths)

# Ensure app is fresh
echo "Stopping app..."
am force-stop "$PACKAGE"
sleep 2

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch app to warm it up
echo "Launching app..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Attempt to dismiss standard ads/popups if they appear on start
input keyevent KEYCODE_BACK
sleep 1

# If we accidentally backed out of the app, relaunch
if dumpsys window | grep mCurrentFocus | grep -q "Launcher"; then
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
fi

echo "=== Setup Complete ==="