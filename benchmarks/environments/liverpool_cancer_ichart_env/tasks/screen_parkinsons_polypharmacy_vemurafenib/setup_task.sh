#!/bin/bash
set -e
echo "=== Setting up Parkinson's Polypharmacy Screen Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define package name
PACKAGE="com.liverpooluni.ichartoncology"

# Ensure device is connected
adb wait-for-device

# Clean up any previous task artifacts on the device
adb shell rm -f /sdcard/parkinsons_safety_report.txt 2>/dev/null || true

# Force stop the app to ensure a clean start
echo "Restarting application..."
adb shell am force-stop $PACKAGE
sleep 2

# Launch the app to the main activity
adb shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure we are at the start state (Home screen of the app)
# We can try to press back a few times just in case, or rely on force-stop
# Force stop usually resets the stack, so just launching is enough.

# Capture initial state screenshot
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="