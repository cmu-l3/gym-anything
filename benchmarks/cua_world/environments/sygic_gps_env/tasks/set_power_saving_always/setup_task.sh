#!/system/bin/sh
# Setup script for set_power_saving_always task

echo "=== Setting up set_power_saving_always task ==="

# 1. timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Define package
PACKAGE="com.sygic.aura"

# 3. Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# 4. Ensure we are at Home screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 6. Verify launch
if pidof $PACKAGE > /dev/null; then
    echo "Sygic launched successfully"
else
    echo "ERROR: Sygic failed to launch"
    # Try one more time
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# 7. Reset power saving pref if possible (requires root/debug access)
# This is a "best effort" to ensure the task isn't already done
# We try to seduce the config to default '0' (On battery) or similar if we can find it
# Since specific file location varies by version, we rely on the clean state of the env mostly.

echo "=== Task setup complete ==="