#!/system/bin/sh
# Post-start setup script for Subway Surfers
# Immersive mode is disabled by the AVD runner automatically

echo "=== Setting up Subway Surfers Environment ==="

sleep 3
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="com.kiloo.subwaysurf"

pm list packages | grep -q "$PACKAGE"
if [ $? -eq 0 ]; then
    echo "Subway Surfers: INSTALLED"
else
    echo "ERROR: Subway Surfers not installed!"
    exit 1
fi

echo "Launching Subway Surfers..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1

# Wait for game to fully load (loading takes ~40-60 seconds)
echo "Waiting for game to load (60 seconds)..."
sleep 60

# Handle age verification dialog
# Right arrow to increase age is at (900, 1400)
echo "Setting age to 25..."
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
input tap 900 1400
sleep 2

# Tap Confirm button at (540, 1600)
echo "Confirming age..."
input tap 540 1600
sleep 10

# Tap "Tap to Play" at (540, 2100) - this gets to main menu
echo "Tapping to play..."
input tap 540 2100
sleep 5

# Tap center to dismiss any tutorials and start a run
# The main menu has "Play" button area in center-bottom
echo "Starting a run..."
input tap 540 1800
sleep 3

# Additional tap to ensure we're in gameplay
input tap 540 1400
sleep 2

echo "=== Subway Surfers setup completed ==="
echo "Game should be ready for agent interaction"
