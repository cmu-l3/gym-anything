#!/system/bin/sh
# setup_task.sh for check_acid_reducer_with_erlotinib@1

echo "=== Setting up check_acid_reducer_with_erlotinib task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.liverpooluni.ichartoncology"

# Ensure app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart is not installed!"
    exit 1
fi

# Force stop the app to ensure clean state
am force-stop $PACKAGE
sleep 1

# Remove any previous result file to prevent reading stale data
rm -f /sdcard/erlotinib_omeprazole_result.txt
rm -f /sdcard/task_result.json

# Press Home to ensure clean starting point
input keyevent KEYCODE_HOME
sleep 2

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="