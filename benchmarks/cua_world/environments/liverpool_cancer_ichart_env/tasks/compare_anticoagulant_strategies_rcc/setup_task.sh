#!/system/bin/sh
# Setup script for compare_anticoagulant_strategies_rcc
# Runs inside Android environment

echo "=== Setting up RCC Anticoagulant Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Clean previous artifacts
rm -f /sdcard/rcc_anticoagulant_matrix.txt
rm -f /sdcard/task_result.json

# 2. Record start time (using date +%s if available, or just touch a file)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || touch /sdcard/task_start_time.txt

# 3. Ensure app is in a clean state (force stop)
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Return to Home Screen
echo "Going to Home Screen..."
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch App (Warmup)
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart
# 6. Ensure we are at the main menu (back out of any deep navigation if state persisted)
# Press back a few times just in case, though force-stop usually resets it
input keyevent KEYCODE_BACK
sleep 0.5
input keyevent KEYCODE_BACK
sleep 0.5

# Relaunch to be sure
launch_cancer_ichart

echo "=== Setup Complete ==="