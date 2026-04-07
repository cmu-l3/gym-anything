#!/system/bin/sh
# Setup script for spray_day_audit_reconciliation task.
# Clears app data for a clean state and launches farmOS Field Kit to the Tasks screen.
# The agent must then create 3 logs, edit one, configure server, and toggle location.

echo "=== Setting up spray_day_audit_reconciliation task ==="

PACKAGE="org.farmos.app"

# Force stop and clear data for a guaranteed clean state
am force-stop $PACKAGE
sleep 1
pm clear $PACKAGE
sleep 2

# Press Home to ensure a known starting point
input keyevent KEYCODE_HOME
sleep 1

# Re-grant location permissions after pm clear wipes them
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Delete stale output files from any previous run BEFORE recording timestamp
rm -f /sdcard/task_result_spray_audit.json 2>/dev/null
rm -f /sdcard/ui_dump_spray_audit.xml 2>/dev/null
rm -f /sdcard/final_screenshot_spray_audit.png 2>/dev/null
rm -f /sdcard/task_start_time.txt 2>/dev/null

# Record task start timestamp for anti-gaming check
date +%s > /sdcard/task_start_time.txt

# Launch app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# Verify app is in foreground; relaunch if stuck on Launcher
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 4
fi

echo "=== spray_day_audit_reconciliation setup complete ==="
echo "App should be on empty Tasks screen."
echo "Agent must: create 3 logs, edit first log, configure server, disable location sharing."
