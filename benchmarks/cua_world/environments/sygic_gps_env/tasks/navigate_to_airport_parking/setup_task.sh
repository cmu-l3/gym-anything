#!/system/bin/sh
# Setup script for navigate_to_airport_parking
# Runs inside Android environment

echo "=== Setting up navigate_to_airport_parking task ==="

PACKAGE="com.sygic.aura"

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Force stop Sygic to ensure a clean state
echo "Stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# 3. Set Mock Location to Mountain View (Start Point)
# This ensures a consistent route calculation to SFO
# Latitude: 37.4220, Longitude: -122.0841
# Note: In some emulator setups, this requires 'telnet localhost 5554' or appops
# We will try to grant permissions just in case
appops set $PACKAGE android:mock_location allow 2>/dev/null

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load (Main Map Screen)
sleep 15

# 6. Ensure we are on the map (press Back just in case a dialog is open)
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# If back exited the app, relaunch
if ! pidof $PACKAGE > /dev/null; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 7. Take initial screenshot evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="