#!/system/bin/sh
# Setup script for access_pfd_display task
# Runs on Android device

echo "=== Setting up access_pfd_display task ==="

PACKAGE="com.ds.avare"
START_TIME=$(date +%s)
echo "$START_TIME" > /sdcard/task_start_time.txt

# 1. Ensure Avare is running
echo "Starting Avare..."
. /sdcard/scripts/launch_helper.sh
launch_avare

# 2. Ensure we are on the Map tab (Default)
# We can try to force it by restarting the activity or sending a specific intent,
# but simplest is to just launch the main activity.

# 3. Handle potential "Exit" dialogs if previous session crashed
# Tap Back once just in case a menu is open
input keyevent KEYCODE_BACK 2>/dev/null
sleep 1

# 4. Verify app is in foreground
CURRENT_FOCUS=$(dumpsys window windows | grep -i "mCurrentFocus")
echo "Initial Focus: $CURRENT_FOCUS"

# Capture initial screenshot for debugging
screencap -p /sdcard/task_initial_state.png

echo "=== Setup Complete ==="