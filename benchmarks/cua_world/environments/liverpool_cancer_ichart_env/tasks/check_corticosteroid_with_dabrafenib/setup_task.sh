#!/system/bin/sh
# Setup script for check_corticosteroid_with_dabrafenib
# Runs on Android device

echo "=== Setting up task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_PATH="/sdcard/dabrafenib_dexamethasone_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Record start time for anti-gaming
date +%s > "$START_TIME_FILE"

# 2. Clean up previous artifacts
rm -f "$REPORT_PATH" 2>/dev/null
rm -f "/sdcard/task_result.json" 2>/dev/null

# 3. Ensure app is closed to start fresh
am force-stop "$PACKAGE"
sleep 2

# 4. Return to Home Screen
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Take initial screenshot (optional, usually handled by framework, but good for debug)
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="