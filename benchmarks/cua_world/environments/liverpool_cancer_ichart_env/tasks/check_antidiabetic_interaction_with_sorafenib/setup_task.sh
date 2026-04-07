#!/system/bin/sh
# Setup script for check_antidiabetic_interaction_with_sorafenib
# Runs inside Android environment

echo "=== Setting up Sorafenib-Metformin Interaction Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Clean up previous state
echo "Cleaning up previous artifacts..."
rm -f /sdcard/interaction_result.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# 2. Record start time (using date +%s if available, else touch a reference file)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || touch /sdcard/task_start_ref_file

# 3. Ensure app is closed (Agent must launch it)
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Go to Home Screen
echo "Navigating to Home Screen..."
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 1

# 5. Clear clipboard (optional, to prevent data leakage)
service call clipboard 2 s16 "" 2>/dev/null || true

# 6. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== Setup Complete ==="