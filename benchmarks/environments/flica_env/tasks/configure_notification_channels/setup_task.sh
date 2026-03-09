#!/system/bin/sh
set -e
echo "=== Setting up configure_notification_channels task ==="

PACKAGE="com.robert.fcView"

# 1. Record task start time (anti-gaming)
date +%s > /sdcard/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /sdcard/notification_config.txt
rm -f /sdcard/task_result.json

# 3. Ensure Flight Crew View is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Flight Crew View not installed"
    exit 1
fi

# 4. Ensure logged in (Notifications often don't register until after login/prompt)
sh /sdcard/scripts/login_helper.sh

# 5. Reset/Ensure Notifications are enabled globally for the app
# (Requires root/shell, which we have)
cmd notification set_notifications_enabled_for_package $PACKAGE 1000 1

# 6. Trigger app to register channels (launch main activity)
am start -n "$PACKAGE/com.robert.fcView.MainActivity" 2>/dev/null
sleep 5

# 7. Record initial channel state
cmd notification list_channels $PACKAGE 1000 > /sdcard/initial_channels.txt 2>/dev/null || true

# 8. Return to Home Screen to give agent a clean slate
input keyevent KEYCODE_HOME
sleep 2

# 9. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="