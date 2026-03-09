#!/system/bin/sh
# Setup script for livestock_health_treatment_log task.
# Clears app data for a clean state and launches farmOS Field Kit.

echo "=== Setting up livestock_health_treatment_log task ==="

PACKAGE="org.farmos.app"

am force-stop $PACKAGE
sleep 1
pm clear $PACKAGE
sleep 2

input keyevent KEYCODE_HOME
sleep 1

pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

date +%s > /sdcard/task_start_livestock.txt

echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 6
fi

echo "=== livestock_health_treatment_log setup complete ==="
echo "App should be on empty Tasks screen. Agent must create 5 livestock health event logs."
