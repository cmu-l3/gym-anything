#!/system/bin/sh
# Setup script for crop_spray_day_records task.
# Clears app data for a clean state and launches farmOS Field Kit to the Tasks screen.

echo "=== Setting up crop_spray_day_records task ==="

PACKAGE="org.farmos.app"

# Force stop and clear data for clean state
am force-stop $PACKAGE
sleep 1
pm clear $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Grant location permissions again after clear
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Record task start timestamp
date +%s > /sdcard/task_start_crop_spray.txt

# Launch app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 6
fi

echo "=== crop_spray_day_records setup complete ==="
echo "App should be on empty Tasks screen. Agent must create 5 spray day logs."
