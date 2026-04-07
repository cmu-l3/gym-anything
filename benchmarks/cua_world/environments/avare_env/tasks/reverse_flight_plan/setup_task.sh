#!/system/bin/sh
# Setup script for reverse_flight_plan task
# Runs on Android device

echo "=== Setting up Reverse Flight Plan Task ==="

PACKAGE="com.ds.avare"

# 1. Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Force stop app to ensure fresh start
am force-stop $PACKAGE
sleep 2

# 3. Launch Avare
echo "Launching Avare..."
. /sdcard/scripts/launch_helper.sh
launch_avare

# 5. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="