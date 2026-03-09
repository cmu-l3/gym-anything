#!/system/bin/sh
# Setup script for check_multiple_comedications task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up check_multiple_comedications task ==="

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

echo "=== check_multiple_comedications task setup complete ==="
echo "App should be on Welcome screen. Agent should select a cancer drug and two co-medications to check multiple interactions."
