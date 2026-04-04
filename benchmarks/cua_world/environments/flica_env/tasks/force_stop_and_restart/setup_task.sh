#!/system/bin/sh
echo "=== Setting up force_stop_and_restart task ==="

PACKAGE="com.robert.fcView"

# 1. Record Task Start Time
date +%s > /sdcard/task_start_time.txt

# 2. Ensure App is Running and Logged In
# We use the helper to ensure we are in a good state (Friends View)
sh /sdcard/scripts/login_helper.sh

# 3. Get Initial Process ID (PID)
# Wait a moment for process to settle
sleep 2
INITIAL_PID=$(pidof $PACKAGE)

if [ -z "$INITIAL_PID" ]; then
    echo "ERROR: App failed to start during setup."
    exit 1
fi

echo "$INITIAL_PID" > /sdcard/initial_pid.txt
echo "Initial PID: $INITIAL_PID"

# 4. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="