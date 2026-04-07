#!/system/bin/sh
echo "=== Setting up Map-Based Destination Selection Task ==="

PACKAGE="com.sygic.aura"

# Record start time
date +%s > /sdcard/tasks/task_start_time.txt

# 1. Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Press Home to clear any UI clutter
input keyevent KEYCODE_HOME
sleep 1

# 3. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Handle potential "Resume" or "Rate us" dialogs
# Tap vaguely in the center/bottom to dismiss generic overlays if present
input tap 540 1800
sleep 2

# 5. Ensure we are on the map view (Press Back a few times to exit menus)
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# 6. Take initial screenshot
screencap -p /sdcard/tasks/initial_state.png

echo "=== Setup Complete ==="