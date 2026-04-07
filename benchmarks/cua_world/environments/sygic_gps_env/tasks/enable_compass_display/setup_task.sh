#!/system/bin/sh
echo "=== Setting up enable_compass_display task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI navigation stack
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (warmup)
sleep 10

# Ensure we are not in a menu by pressing back a few times if needed, 
# but since we force stopped, it should start at main map or splash.
# Just in case of "Resume route?" dialogs or similar:
# We'll just wait. The agent handles popups.

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="