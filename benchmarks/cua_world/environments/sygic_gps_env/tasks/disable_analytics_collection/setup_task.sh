#!/system/bin/sh
echo "=== Setting up disable_analytics_collection task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Ensure clean state by force stopping
am force-stop $PACKAGE
sleep 2

# Launch application
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 10

# Ensure we are not on a crash dialog or splash screen
# Press Back once just in case a menu was left open from previous run (if persistence exists)
input keyevent KEYCODE_BACK
sleep 1

# If we are at the "Exit App?" dialog, cancel it
# (Assuming naive back press might trigger exit on main map)
# We'll just rely on the fresh launch usually resetting the view stack or bringing existing to front

# Capture initial state for debugging/verification
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="