#!/system/bin/sh
echo "=== Setting up set_pedestrian_mode task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to clear any overlays
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Ensure we are on the main screen (dismiss any 'Map ready' dialogs)
# Tap roughly in the center-bottom to dismiss bottom sheets if any
input tap 540 1600
sleep 1

# Capture initial state screenshot
screencap -p /sdcard/task_initial.png

# Verify app is running
if pidof com.sygic.aura > /dev/null; then
    echo "App launched successfully"
else
    echo "ERROR: App failed to launch"
fi

echo "=== Task setup complete ==="