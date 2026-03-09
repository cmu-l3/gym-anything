#!/system/bin/sh
# setup_task.sh for track_flight_alert@1
# Ensures app is logged in and on the Friends home page

set -e
echo "=== Setting up track_flight_alert task ==="

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.robert.fcView"

# Run the login helper to ensure we're logged in and on the Friends page
# This helper handles the full login flow or resets state if needed
sh /sdcard/scripts/login_helper.sh
sleep 3

# Verify we're on the Friends page by checking UI content
uiautomator dump /sdcard/setup_verify.xml 2>/dev/null
sleep 1

if [ -f /sdcard/setup_verify.xml ]; then
    # Look for characteristic text of the Friends/Home screen
    if cat /sdcard/setup_verify.xml | grep -q "Friends\|Add New Friend\|friend"; then
        echo "Confirmed: On Friends page"
    else
        echo "WARNING: May not be on Friends page, attempting relaunch..."
        am force-stop $PACKAGE
        sleep 2
        sh /sdcard/scripts/login_helper.sh
        sleep 5
    fi
fi

# Save initial UI state hash for "do nothing" detection
uiautomator dump /sdcard/initial_ui_state.xml 2>/dev/null
if [ -f /sdcard/initial_ui_state.xml ]; then
    md5sum /sdcard/initial_ui_state.xml | cut -d' ' -f1 > /sdcard/initial_ui_hash.txt
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial_screenshot.png 2>/dev/null

# Clean up verify file
rm -f /sdcard/setup_verify.xml

echo "=== Task setup complete ==="
echo "App is logged in as Friend/Family on the Friends home page."