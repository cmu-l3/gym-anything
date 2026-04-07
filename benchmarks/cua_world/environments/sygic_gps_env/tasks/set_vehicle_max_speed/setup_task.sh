#!/system/bin/sh
# Setup script for set_vehicle_max_speed task
# Android environment uses /system/bin/sh

echo "=== Setting up set_vehicle_max_speed task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Dismiss any potential overlays/dialogs (basic cleanup)
# Tap center-bottom to dismiss "Map ready" sheet if present
input tap 540 1800 2>/dev/null
sleep 1

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="