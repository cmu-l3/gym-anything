#!/bin/bash
set -e
echo "=== Setting up Select Safe Antidepressant Task ==="

# Define variables
PACKAGE="com.liverpooluni.ichartoncology"
TASK_START_FILE="/tmp/task_start_time.txt"
OUTPUT_FILE="/sdcard/vandetanib_depression_plan.txt"

# 1. Record trusted start time on host (for anti-gaming)
date +%s > "$TASK_START_FILE"

# 2. Clean up previous artifacts on device
echo "Cleaning up previous task artifacts..."
adb shell rm -f "$OUTPUT_FILE" 2>/dev/null || true

# 3. Ensure clean app state
echo "Force stopping app..."
adb shell am force-stop "$PACKAGE"
sleep 2

# 4. Launch app to initial state
echo "Launching Cancer iChart..."
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

# 5. Handle potential "Welcome" or "Disclaimer" screens if they appear on cold start
# (Simple tap in center/bottom often clears generic splash screens, but we assume
# the env setup script handles the one-time database download. We just ensure it's open.)
# We will verify the app is in foreground.
FOCUSED_APP=$(adb shell dumpsys window | grep mCurrentFocus || echo "")
if [[ "$FOCUSED_APP" != *"$PACKAGE"* ]]; then
    echo "WARNING: App did not come to foreground. Retrying..."
    adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 5
fi

# 6. Take initial screenshot
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png >/dev/null 2>&1

echo "=== Task setup complete ==="