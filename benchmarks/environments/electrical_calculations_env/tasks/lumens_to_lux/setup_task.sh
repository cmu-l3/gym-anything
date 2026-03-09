#!/system/bin/sh
# Setup script for lumens_to_lux task.
# Launches Electrical Calculations app to the main menu.

echo "=== Setting up lumens_to_lux task ==="

PACKAGE="com.hsn.electricalcalculations"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss any ad overlay by pressing back
input keyevent KEYCODE_BACK
sleep 2

# Relaunch if we ended up on home screen
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== lumens_to_lux task setup complete ==="
echo "App should be on main menu. Agent should scroll down and navigate to Lumens to Lux."
