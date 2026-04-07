#!/system/bin/sh
echo "=== Setting up customize_map_shortcuts task ==="

PACKAGE="com.ds.avare"

# 1. Record Start Time for Anti-Gaming
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean start state
# We don't want to wipe all data (maps), but we want to ensure the app is fresh
echo "Stopping Avare..."
am force-stop $PACKAGE
sleep 2

# 3. Launch App
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 4. Handle any potential startup dialogs (like 'Download Maps')
# Tap Back once just in case a dialog is open, to get to Map
input keyevent KEYCODE_BACK
sleep 1

# 5. Ensure we are on the Map screen
# Relaunching usually brings front; if Back exited, relaunch
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="