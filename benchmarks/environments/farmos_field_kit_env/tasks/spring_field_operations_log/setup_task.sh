#!/system/bin/sh
# Setup script for spring_field_operations_log task.
# Clears app data for a clean state and launches farmOS Field Kit.

echo "=== Setting up spring_field_operations_log task ==="

PACKAGE="org.farmos.app"

am force-stop $PACKAGE
sleep 1
pm clear $PACKAGE
sleep 2

input keyevent KEYCODE_HOME
sleep 1

pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

date +%s > /sdcard/task_start_spring.txt

echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 6
fi

echo "=== spring_field_operations_log setup complete ==="
echo "App should be on empty Tasks screen. Agent must create 5 spring planting day logs."
