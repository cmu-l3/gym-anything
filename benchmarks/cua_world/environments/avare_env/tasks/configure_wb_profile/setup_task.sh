#!/system/bin/sh
# Setup script for configure_wb_profile task.
# Launches Avare and ensures a clean state.

echo "=== Setting up Weight & Balance Task ==="

PACKAGE="com.ds.avare"

# Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean start
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are on the main map (handle any resume logic if needed)
# Avare usually resumes last screen, so we might need to back out if stuck in a menu
# Sending BACK key a couple times just in case, but usually force stop resets view stack
input keyevent KEYCODE_BACK
sleep 1

# If app closed due to back, relaunch
if ! pidof com.ds.avare > /dev/null; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Capture initial state
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="