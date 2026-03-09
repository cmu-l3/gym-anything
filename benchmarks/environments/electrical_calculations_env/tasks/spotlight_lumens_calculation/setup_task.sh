#!/system/bin/sh
set -e
echo "=== Setting up Spotlight Lumens Calculation task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.hsn.electricalcalculations"

# 1. Force stop to ensure a clean state (no stale calculations)
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# 2. Launch the application to the main menu
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# 3. Handle potential startup dialogs/ads
# Press Back once to dismiss common full-screen ads/dialogs
input keyevent KEYCODE_BACK
sleep 2

# Relaunch to ensure we are at the main activity, not exited
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 3

# 4. Take initial screenshot for evidence
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

# 5. Clean up any previous results
rm -f /sdcard/spotlight_results.txt 2>/dev/null || true

echo "=== Task setup complete ==="