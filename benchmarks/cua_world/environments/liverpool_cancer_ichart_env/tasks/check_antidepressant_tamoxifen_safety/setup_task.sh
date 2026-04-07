#!/system/bin/sh
set -e
echo "=== Setting up check_antidepressant_tamoxifen_safety task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/interaction_report.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# 3. Ensure app is in a clean state (force stop)
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# 4. Return to Home screen to ensure known starting state
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Capture initial state screenshot for evidence
screencap -p /sdcard/initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="