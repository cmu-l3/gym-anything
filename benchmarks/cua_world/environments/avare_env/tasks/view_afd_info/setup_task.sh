#!/system/bin/sh
# Setup script for view_afd_info task
# Android environment uses /system/bin/sh

echo "=== Setting up view_afd_info task ==="

# 1. Create task directory if it doesn't exist
mkdir -p /sdcard/tasks/view_afd_info

# 2. Record task start time (using date +%s if available, or just date)
date +%s > /sdcard/tasks/view_afd_info/task_start_time.txt 2>/dev/null || date > /sdcard/tasks/view_afd_info/task_start_time.txt

# 3. Ensure Avare is in a clean state (force stop)
PACKAGE="com.ds.avare"
am force-stop $PACKAGE
sleep 2

# 4. Launch Avare to the main activity
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Dismiss any potential dialogs (Sim mode, etc) by pressing Back once
# Just in case a dialog is blocking the view
input keyevent KEYCODE_BACK
sleep 1

# 6. Ensure we are at the Map tab (default) to standardise start state
# We can't easily force tabs via intent, but a fresh launch usually goes to Map.
# We will verify the start state via screenshot.

# 7. Take initial screenshot for anti-gaming comparison
screencap -p /sdcard/tasks/view_afd_info/initial_state.png

echo "=== Task setup complete ==="