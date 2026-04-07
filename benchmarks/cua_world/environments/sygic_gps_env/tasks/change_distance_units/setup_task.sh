#!/system/bin/sh
# Setup script for change_distance_units task.
# Launches Sygic GPS to the main map screen.

echo "=== Setting up change_distance_units task ==="

PACKAGE="com.sygic.aura"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

echo "=== change_distance_units task setup complete ==="
echo "App should be on main map screen. Agent should navigate to Settings > View & Units > Distance units."
