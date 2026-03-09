#!/system/bin/sh
# Setup script for olaparib_antiepileptic_interaction_consultation task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up olaparib_antiepileptic_interaction_consultation task ==="

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

echo "=== olaparib_antiepileptic_interaction_consultation task setup complete ==="
echo "App is on Welcome screen."
echo "Screen carbamazepine, warfarin, and acenocoumarol against olaparib."
echo "Navigate to the Interaction Details for olaparib + carbamazepine."
