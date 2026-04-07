#!/system/bin/sh
# Setup script for lumens_to_candela task
# Runs on Android device

echo "=== Setting up lumens_to_candela task ==="

TASK_DIR="/sdcard/tasks/lumens_to_candela"
PACKAGE="com.hsn.electricalcalculations"

# 1. Create task directory
mkdir -p "$TASK_DIR"
rm -f "$TASK_DIR/result.txt"
rm -f "$TASK_DIR/screenshot.png"
rm -f "$TASK_DIR/task_result.json"

# 2. Record start timestamp (seconds)
date +%s > "$TASK_DIR/start_time.txt"

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch app to main menu
echo "Launching app..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# 6. Take initial screenshot for evidence
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup complete ==="