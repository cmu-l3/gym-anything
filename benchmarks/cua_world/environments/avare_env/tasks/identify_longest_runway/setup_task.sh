#!/system/bin/sh
# Setup script for identify_longest_runway task
# Runs inside the Android environment

echo "=== Setting up identify_longest_runway task ==="

PACKAGE="com.ds.avare"

# 1. Clean up previous artifacts
rm -f /sdcard/longest_runway.txt
rm -f /sdcard/task_result.json

# 2. Record task start time (using date +%s if available, else generic marker)
# Android's shell date usually supports +%s
date +%s > /sdcard/task_start_time.txt
echo "Task start time recorded: $(cat /sdcard/task_start_time.txt)"

# 3. Ensure Avare is running and on the main map
# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Launch the app
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Handle potential "What's New" or startup dialogs by sending Back key if needed
# But usually fresh install setup is handled by env setup. 
# We just ensure we are on map.
# Verify app is in foreground
if ! dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 4. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png 2>/dev/null

echo "=== Task setup complete ==="