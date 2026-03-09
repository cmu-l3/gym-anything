#!/bin/bash
set -e
echo "=== Setting up Verify Contraceptive Safety Task ==="

# Define package name
PACKAGE="com.liverpooluni.ichartoncology"

# 1. Record task start time (container time)
date +%s > /tmp/task_start_time.txt

# 2. Sync Android time (optional, but good for consistency)
# adb shell settings put global auto_time 1 2>/dev/null || true

# 3. Clean up previous task artifacts on Android
echo "Cleaning up old files..."
adb shell rm -f /sdcard/contraceptive_check.txt 2>/dev/null || true

# 4. Ensure App is installed (Environment should handle this, but verify)
if ! adb shell pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: App $PACKAGE not found!"
    # In a real scenario, we might try to reinstall, but here we assume env is correct.
    exit 1
fi

# 5. Reset App State (Force Stop)
echo "Force stopping app..."
adb shell am force-stop $PACKAGE
sleep 2

# 6. Launch App to Home Screen
echo "Launching app..."
adb shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 7. Take initial screenshot for evidence
echo "Capturing initial state..."
adb exec-out screencap -p > /tmp/task_initial.png

echo "=== Setup Complete ==="