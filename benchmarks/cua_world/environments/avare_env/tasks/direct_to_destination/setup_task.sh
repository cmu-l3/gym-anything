#!/system/bin/sh
set -e
echo "=== Setting up Direct-To Destination task ==="

# Record task start time for anti-gaming verification
date +%s > /data/local/tmp/task_start_time.txt

PACKAGE="com.ds.avare"

# Force stop Avare to ensure clean state
am force-stop $PACKAGE
sleep 2

# Clear any existing destination/plan state
# We remove specific state files to force the agent to actually perform the task
# Location of files typically: /data/data/com.ds.avare/files/
echo "Clearing previous navigation state..."
run-as $PACKAGE rm -f /data/data/$PACKAGE/files/save.xml 2>/dev/null || true
run-as $PACKAGE rm -f /data/data/$PACKAGE/files/plan.txt 2>/dev/null || true
run-as $PACKAGE rm -f /data/data/$PACKAGE/files/destination.txt 2>/dev/null || true

# Launch Avare fresh
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Handle any potentially blocking dialogs (e.g. "Download Data")
# Press Back to dismiss dialogs if present
input keyevent KEYCODE_BACK
sleep 2

# Ensure we are on the map screen (sometimes back exits the app, so we check)
# If app is not in foreground, relaunch
if ! dumpsys window | grep -q "mCurrentFocus.*$PACKAGE"; then
    echo "App closed, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take screenshot of initial state
screencap -p /data/local/tmp/task_initial_state.png 2>/dev/null || true

echo "=== Direct-To Destination task setup complete ==="