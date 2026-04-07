#!/system/bin/sh
# Setup script for plan_remote_route task.
# Runs inside the Android environment.

echo "=== Setting up plan_remote_route task ==="

PACKAGE="com.sygic.aura"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Force stop Sygic to ensure clean state (no previous routes)
am force-stop $PACKAGE
sleep 2

# 3. Return to Home screen
input keyevent KEYCODE_HOME
sleep 1

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 5. Handle potential startup interruptions
# If the app crashed previously or was in navigation, it might ask to restore.
# We'll try to dismiss generic dialogs just in case, though force-stop usually resets.
# Tapping 'Cancel' coordinates (approximate bottom left) or Back key
input keyevent KEYCODE_BACK
sleep 1

# 6. Ensure we are on the map view
# If we are stuck in a menu, press back a few times
# But not too many to exit the app
# The best way is to send an intent, but Sygic doesn't expose a clear 'show map' intent.
# We assume force-stop + launch brings us to the main map.

# 7. Take initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="