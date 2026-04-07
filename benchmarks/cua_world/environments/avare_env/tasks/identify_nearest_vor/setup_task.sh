#!/system/bin/sh
# setup_task.sh - Set up for identify_nearest_vor task
set -e
echo "=== Setting up identify_nearest_vor task ==="

# Record task start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# Remove any previous result file to ensure fresh creation
rm -f /sdcard/nearest_vor_result.txt
rm -f /sdcard/task_result.json

PACKAGE="com.ds.avare"

# Force stop Avare to get clean state
am force-stop $PACKAGE
sleep 2

# Ensure we are at Home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch Avare fresh
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Handle potential "Required data file" dialog or other startups
# Tap 'Cancel' or 'Back' just in case to get to map
input keyevent KEYCODE_BACK 2>/dev/null
sleep 1

# Take screenshot of initial state
screencap -p /sdcard/task_initial_state.png

echo "=== identify_nearest_vor task setup complete ==="