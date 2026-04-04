#!/system/bin/sh
# Setup script for check_combo_therapy_beta_blocker_safety task

echo "=== Setting up Combo Therapy Safety Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_PATH="/sdcard/combo_safety_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_PATH"
rm -f "/sdcard/task_result.json"

# 2. Record start time (using standard Unix timestamp)
date +%s > "$START_TIME_FILE"
echo "Task start time recorded: $(cat $START_TIME_FILE)"

# 3. Ensure app is closed to start fresh
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 1

# 4. Return to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch app to ensure it's ready (optional, but good for stability)
# The description asks the agent to launch it, but ensuring it's installed/launchable is good.
# We will leave it closed so the agent has to launch it as per instructions.

echo "=== Setup Complete ==="