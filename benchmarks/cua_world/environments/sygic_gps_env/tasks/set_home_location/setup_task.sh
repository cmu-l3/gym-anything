#!/system/bin/sh
set -e
echo "=== Setting up set_home_location task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home to ensure clean background
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Handle "Your map is ready" bottom sheet if it appears
# Tap X at roughly [860, 1510] (based on env setup script)
input tap 860 1510 2>/dev/null || true
sleep 2

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# Take initial state screenshot for anti-gaming comparison
screencap -p /sdcard/task_initial.png
echo "Initial screenshot captured"

echo "=== set_home_location task setup complete ==="