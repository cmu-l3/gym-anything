#!/system/bin/sh
# setup_check_antiarrhythmic.sh
# Setup for checking Dasatinib + Amiodarone interaction

echo "=== Setting up check_antiarrhythmic_with_dasatinib task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous task artifacts
rm -f /sdcard/task_result.txt
rm -f /sdcard/task_result.json

# 3. Ensure clean state: Force stop the app
echo "Force stopping Cancer iChart..."
am force-stop $PACKAGE 2>/dev/null
sleep 2

# 4. Return to Home Screen
echo "Returning to Home Screen..."
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Take initial screenshot (evidence of starting state)
screencap -p /sdcard/task_initial_state.png

echo "=== Setup complete ==="