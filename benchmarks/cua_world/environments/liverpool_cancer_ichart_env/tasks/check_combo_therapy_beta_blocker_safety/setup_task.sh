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

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== Setup Complete ==="