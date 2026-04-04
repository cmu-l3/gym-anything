#!/system/bin/sh
# Setup script for check_red_interaction task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up check_red_interaction task ==="

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

echo "=== check_red_interaction task setup complete ==="
echo "App should be on Welcome screen. Agent should search for Crizotinib + Ketoconazole to find a red 'Do Not Coadminister' result."
