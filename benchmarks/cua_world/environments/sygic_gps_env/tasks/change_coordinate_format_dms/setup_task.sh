#!/system/bin/sh
# Setup script for change_coordinate_format_dms task
# Runs inside the Android environment

echo "=== Setting up change_coordinate_format_dms task ==="

PACKAGE="com.sygic.aura"

# 1. timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean state (force stop)
echo "Stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# 3. Launch Application
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 4. Handle any 'Resume' or startup dialogs if needed
# (Assuming env setup script handled EULA/Login, just need to ensure we are on map)
# Tap center to dismiss potential 'Map ready' sheet
input tap 540 1000
sleep 1

# 5. Capture initial state
screencap -p /sdcard/task_initial.png
echo "Initial state captured to /sdcard/task_initial.png"

echo "=== Task setup complete ==="