#!/system/bin/sh
# Setup script for change_chart_type task.
# Launches Avare to the main map screen.

echo "=== Setting up change_chart_type task ==="

PACKAGE="com.ds.avare"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Grant permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch app
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== change_chart_type task setup complete ==="
echo "App should be on main map screen with default Sectional chart. Agent should change to IFR Low."
