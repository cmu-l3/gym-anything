#!/system/bin/sh
set -e
echo "=== Setting up configure_server_url task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="org.farmos.app"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Clear app data to ensure no pre-existing server configuration
# This ensures the agent starts from the "Welcome" or "Login" state
pm clear $PACKAGE > /dev/null 2>&1 || true
sleep 1

# Re-grant permissions after clear (location is often requested)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Go to home screen to give agent a clear starting point
input keyevent KEYCODE_HOME
sleep 2

# Take initial state screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="
echo "App data cleared. Agent must launch app and configure server URL."