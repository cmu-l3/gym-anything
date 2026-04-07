#!/bin/bash
set -e
echo "=== Setting up set_economical_route task ==="

# Define variables
PACKAGE="com.sygic.aura"
TASK_DIR="/workspace/tasks/set_economical_route"
mkdir -p "$TASK_DIR"

# Record task start time (host time) for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure ADB is connected (wait loop)
echo "Waiting for device..."
adb wait-for-device

# 1. Force stop app to ensure clean state
echo "Stopping Sygic..."
adb shell am force-stop "$PACKAGE"
sleep 2

# 2. Reset specific preference if possible (optional, to ensure 'Fastest' is default)
# Note: Modifying internal XMLs is risky without root, so we rely on default or previous state.
# We will just record the state.

# 3. Launch Sygic GPS to Main Map
echo "Launching Sygic GPS..."
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 15

# 4. Handle any potential startup popups (Best effort)
# Press Back once just in case a menu/dialog is open
adb shell input keyevent KEYCODE_BACK
sleep 2
# If we exited the app, launch again
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Take initial screenshot
echo "Capturing initial state..."
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png 2>/dev/null || true

# 6. Record initial preferences timestamp (if accessible)
# We try to get the modification time of the prefs file to ensure it changes *after* this point
PREFS_CHECK_CMD="run-as $PACKAGE ls -l /data/data/$PACKAGE/shared_prefs/ 2>/dev/null"
adb shell "$PREFS_CHECK_CMD" > /tmp/initial_prefs_list.txt || echo "Cannot access prefs" > /tmp/initial_prefs_list.txt

echo "=== Task setup complete ==="