#!/bin/bash
echo "=== Setting up check_respiratory_meds_safety_lorlatinib task ==="

# Define App Package
PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time in the container (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure ADB is connected
adb wait-for-device

# Clean up previous task artifacts on the device
echo "Cleaning up previous results..."
adb shell rm -f /sdcard/respiratory_check.txt

# Force stop the app to ensure a clean starting state
echo "Force stopping app..."
adb shell am force-stop $PACKAGE

# Launch the app to the main activity
echo "Launching Cancer iChart..."
adb shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1

# Wait for app to load
sleep 5

# Ensure we are not stuck on a dialog (attempt to press Back if needed, or just let agent handle it)
# We'll just leave it at the start screen. The agent needs to handle navigation.

# Take initial screenshot for evidence
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png

echo "=== Task setup complete ==="