#!/system/bin/sh
# Setup script for create_harvest_log task.
# Clears app data for clean state and launches to Tasks screen.

echo "=== Setting up create_harvest_log task ==="

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

echo "=== create_harvest_log task setup complete ==="
echo "App should be on empty Tasks screen with 'Let's Get Started!' message."
