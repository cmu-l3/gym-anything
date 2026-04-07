#!/system/bin/sh
# Setup script for change_app_interface_language task
# Runs on Android device

echo "=== Setting up change_app_interface_language task ==="

# 1. Record start time for anti-gaming (duration checks)
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean state - Force stop Sygic
PACKAGE="com.sygic.aura"
am force-stop $PACKAGE
sleep 2

# 3. Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Handle any potential startup popups (e.g. "Rate us" or "Premium")
# Pressing Back once is a safe heuristic to dismiss overlays without exiting app
input keyevent KEYCODE_BACK
sleep 2

# 5. Ensure we are on the main map view
# Tap a neutral area to dismiss any bottom sheets
input tap 540 1200
sleep 2

# 6. Take initial screenshot for evidence (Start State)
screencap -p /sdcard/task_initial.png

# 7. Verify app is running
if ps -A | grep -q "com.sygic.aura"; then
    echo "Sygic is running."
else
    echo "ERROR: Sygic failed to start."
    # Try one more time
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Task setup complete ==="