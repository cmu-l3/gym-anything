#!/system/bin/sh
# Setup script for crizotinib_concurrent_comedication_screening task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up crizotinib_concurrent_comedication_screening task ==="

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

echo "=== crizotinib_concurrent_comedication_screening task setup complete ==="
echo "App is on Welcome screen."
echo "Select crizotinib, then select BOTH acenocoumarol AND fluconazole simultaneously."
echo "Remain on the Results screen showing both co-medication interaction results."
