#!/system/bin/sh
# Setup script for restrict_background_data task
# Ensures clean state: Flight Crew View installed, Background Data ALLOWED (default)

echo "=== Setting up restrict_background_data task ==="

PACKAGE="com.robert.fcView"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Record start time
date +%s > "$START_TIME_FILE"

# 2. Ensure App is Installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Package $PACKAGE not found!"
    exit 1
fi

# 3. Get UID
UID=$(pm list packages -U $PACKAGE | grep -o "uid:[0-9]*" | cut -d: -f2)
echo "App UID: $UID"

# 4. Reset Network Policy to Default (Background Data ALLOWED)
# This usually means ensuring it's not in the reject list
# Note: specific commands vary by Android version, but removing from blacklist usually resets it
echo "Resetting network policy..."
cmd netpolicy remove restrict-background-blacklist $UID 2>/dev/null
cmd netpolicy set restrict-background-blacklist $UID false 2>/dev/null

# 5. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME

# 6. Capture initial state evidence
echo "Capturing initial network policy..."
dumpsys netpolicy | grep "$UID" > /sdcard/initial_policy.txt

echo "=== Task setup complete ==="