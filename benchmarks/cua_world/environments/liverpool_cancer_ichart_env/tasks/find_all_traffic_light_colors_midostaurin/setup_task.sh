#!/system/bin/sh
echo "=== Setting up find_all_traffic_light_colors_midostaurin task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.liverpooluni.ichartoncology"

# Force stop the app to ensure a clean starting state
am force-stop $PACKAGE 2>/dev/null
sleep 1

# Ensure we are at the Home screen
input keyevent KEYCODE_HOME
sleep 2

# Verify app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart app is not installed!"
    exit 1
fi

# Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# Take initial screenshot
screencap -p /sdcard/task_initial_state.png 2>/dev/null

echo "=== Task setup complete ==="