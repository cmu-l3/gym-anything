#!/system/bin/sh
# Setup script for search_poi_near_destination task
# Runs on Android device/emulator

echo "=== Setting up search_poi_near_destination task ==="

PACKAGE="com.sygic.aura"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Force stop app to ensure clean state
echo "Stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# 3. Ensure we are at Home screen
input keyevent KEYCODE_HOME
sleep 1

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Handle any potential "Rate us" or "Welcome" dialogs blindly
input keyevent KEYCODE_BACK 2>/dev/null
sleep 1

# 6. Verify app is running
if pidof com.sygic.aura > /dev/null; then
    echo "Sygic is running."
else
    echo "ERROR: Sygic failed to start."
    # Try one more time
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# 7. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="