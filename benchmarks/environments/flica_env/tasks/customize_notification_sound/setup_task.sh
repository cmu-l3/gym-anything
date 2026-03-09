#!/system/bin/sh
# Setup script for customize_notification_sound task

echo "=== Setting up customize_notification_sound task ==="

PACKAGE="com.robert.fcView"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Ensure App is installed and Notification Channels are created
# We launch the app once because channels are often created on first run
echo "Ensuring app is initialized..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5
am force-stop $PACKAGE

# 3. Record Initial Notification State
echo "Recording initial notification state..."
dumpsys notification | grep -A 50 "pkg=$PACKAGE" > /sdcard/initial_notification_state.txt

# 4. Set Initial State: Go to Home Screen
input keyevent KEYCODE_HOME
sleep 2

# 5. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="
echo "Agent starts at Home Screen. Ready to configure settings."