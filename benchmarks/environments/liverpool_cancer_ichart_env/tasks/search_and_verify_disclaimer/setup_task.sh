#!/system/bin/sh
# Setup script for search_and_verify_disclaimer task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up search_and_verify_disclaimer task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== search_and_verify_disclaimer task setup complete ==="
echo "App should be on Welcome screen. Agent should navigate to Disclaimer page and then perform a drug interaction check."
