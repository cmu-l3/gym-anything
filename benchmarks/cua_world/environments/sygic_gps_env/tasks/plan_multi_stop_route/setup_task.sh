#!/system/bin/sh
# setup_task.sh - Prepare Sygic GPS for multi-stop route planning task
set -e
echo "=== Setting up plan_multi_stop_route task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# 2. Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# 3. Take initial screenshot for comparison (baseline)
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Dismiss any common startup dialogs or overlays
# Tap center-bottom to dismiss "Your map is ready" or similar sheets
input tap 540 1800
sleep 2
# Press back once just in case a menu was open or premium upsell appeared
input keyevent KEYCODE_BACK
sleep 2

# 6. Ensure we are on the main map view
# If back took us out of app, relaunch
if ! dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Task setup complete - Sygic on main map view ==="