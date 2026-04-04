#!/system/bin/sh
set -e
echo "=== Setting up check_antiviral_prophylaxis_with_ibrutinib task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/interaction_result.txt
rm -f /sdcard/task_result.json

# 3. Ensure clean app state
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE
sleep 2

# 4. Launch the app to the main screen
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# 5. Dismiss any potential dialogs (like 'What's New' or 'Database Update')
# Pressing back once usually clears overlays without exiting if on main screen
input keyevent KEYCODE_BACK
sleep 1

# 6. Relaunch to ensure we are at the top level
am force-stop $PACKAGE
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 7. Capture initial state
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="