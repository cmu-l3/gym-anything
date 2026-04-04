#!/system/bin/sh
# Setup script for record_daily_egg_harvest
# Ensures a clean state with no previous logs

echo "=== Setting up record_daily_egg_harvest task ==="

PACKAGE="org.farmos.app"

# 1. Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Force stop and clear app data to ensure empty log list
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 3. Grant necessary permissions (clearing data revokes them)
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 4. Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Ensure we are on the main screen (handle any "Welcome" or "Sync" dialogs if they appear, though offline mode usually skips them)
# For farmOS Field Kit offline, it usually goes straight to the log list or a "Server not set" warning which is fine.
# We will press Back once just in case a dialog is open, then ensure we are at the root.
input keyevent KEYCODE_BACK
sleep 1

# Relaunch to be sure
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="