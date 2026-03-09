#!/system/bin/sh
# Setup script for ibrutinib_comedication_contraindication_screen task.
# Launches Cancer iChart to the Welcome screen.

echo "=== Setting up ibrutinib_comedication_contraindication_screen task ==="

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

echo "=== ibrutinib_comedication_contraindication_screen task setup complete ==="
echo "App is on Welcome screen."
echo "Screen acenocoumarol, fluconazole, and ketoconazole against ibrutinib."
echo "Navigate to the Interaction Details for the most severely rated combination."
