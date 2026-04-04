#!/system/bin/sh
set -e
echo "=== Setting up RC Time Constant task ==="

# Define package name
PACKAGE="com.hsn.electricalcalculations"

# Record task start time (for anti-gaming verification)
date +%s > /sdcard/task_start_time.txt

# Force stop the app to ensure a clean start state
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# Go to Home screen
input keyevent KEYCODE_HOME
sleep 2

# Verify we are at home (simple check not easily doable in shell, but input keyevent is reliable)

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="