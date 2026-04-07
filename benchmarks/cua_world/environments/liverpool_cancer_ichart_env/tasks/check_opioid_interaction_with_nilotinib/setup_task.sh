#!/system/bin/sh
# Setup script for check_opioid_interaction_with_nilotinib
# Ensures a clean state with the app closed, requiring the agent to launch it.

echo "=== Setting up Opioid Interaction Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Force stop the app to ensure clean start
echo "Force stopping Cancer iChart..."
am force-stop $PACKAGE
sleep 2

# 2. Go to Home Screen
echo "Navigating to Home Screen..."
input keyevent KEYCODE_HOME
sleep 2

# 3. Clear any background tasks/recents if possible (optional, but good for focus)
# input keyevent KEYCODE_APP_SWITCH
# sleep 1
# input keyevent KEYCODE_DEL
# input keyevent KEYCODE_HOME

# 4. Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Record initial state proof
screencap -p /sdcard/initial_state.png

echo "=== Task Setup Complete ==="