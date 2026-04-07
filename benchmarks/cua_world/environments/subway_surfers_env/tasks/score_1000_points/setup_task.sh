#!/system/bin/sh
# Setup script for score_1000_points task
# Ensures the game is ready to start a new run

echo "=== Setting up score_1000_points task ==="

PACKAGE="com.kiloo.subwaysurf"

# Make sure we're starting fresh - go to home screen first
input keyevent KEYCODE_HOME
sleep 1

# Launch Subway Surfers
echo "Launching Subway Surfers..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Dismiss any dialogs by tapping center
input tap 540 1200
sleep 1

# If at game over screen, tap to continue to main menu
input tap 540 1200
sleep 1

# Tap play button area (center of screen where play button typically is)
# Main menu play button is usually in the center-lower area
input tap 540 1600
sleep 2

# Handle any "Start Run" confirmation or character selection
# Tap center to confirm
input tap 540 1200
sleep 1

echo "=== Task setup completed ==="
echo "Game should be starting or at gameplay screen"
echo "Agent should now play to achieve score >= 1000"
