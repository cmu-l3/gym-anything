#!/system/bin/sh
# Setup script for frost protection activity log task
# Runs via: adb shell sh /sdcard/tasks/record_frost_protection_activity/setup_task.sh

set -e
echo "=== Setting up frost protection activity log task ==="

# Record task start time for anti-gaming verification
date +%s > /data/local/tmp/task_start_time.txt

PACKAGE="org.farmos.app"

# Force stop the app
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# Clear app data to ensure no pre-existing logs (Clean State)
# This is critical for verification: any log found must have been created by the agent
pm clear $PACKAGE 2>/dev/null || true
sleep 2

# Re-grant permissions after clearing data
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true

# Launch the app to the main activity
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# Ensure we are not stuck on a crash dialog or permission prompt
# Press Back once just in case, but usually clear+launch is enough
# input keyevent 4
# sleep 1

# Take initial screenshot
screencap -p /data/local/tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="