#!/system/bin/sh
echo "=== Setting up Transformer Turns Ratio task ==="

PACKAGE="com.hsn.electricalcalculations"
RESULT_FILE="/sdcard/transformer_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous run artifacts
rm -f "$RESULT_FILE"
rm -f "/sdcard/task_result.json"
rm -f "/sdcard/final_screenshot.png"

# 2. Record start time for anti-gaming verification
date +%s > "$START_TIME_FILE"
echo "Task start time recorded: $(cat $START_TIME_FILE)"

# 3. Force stop the app to ensure clean starting state
am force-stop "$PACKAGE"
sleep 1

# 4. Go to Home screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# 6. Take initial screenshot (optional, but good for debugging)
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="