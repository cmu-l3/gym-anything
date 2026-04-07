#!/system/bin/sh
# Setup script for start_route_simulation
# Runs on Android device via adb shell

echo "=== Setting up start_route_simulation task ==="

PACKAGE="com.sygic.aura"

# 1. Clean up previous artifacts
rm -f /sdcard/task_result.json
rm -f /sdcard/task_final.png
rm -f /sdcard/task_start_time.txt

# 2. Record start time (for anti-gaming)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure Sygic is not running (clean state)
am force-stop $PACKAGE
sleep 2

# 4. Press Home to start from neutral ground
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 6. Handle potential startup popups (common in Sygic)
# Attempt to dismiss "Your map is ready" or similar sheets by tapping safely
# Tap roughly center-bottom (dismiss area) and center (ok area)
input tap 860 1510
sleep 1
input tap 540 2200
sleep 1

# 7. Verify App is in foreground
CURRENT_FOCUS=$(dumpsys window windows 2>/dev/null | grep -i "mCurrentFocus")
if echo "$CURRENT_FOCUS" | grep -qi "$PACKAGE"; then
    echo "Sygic launched successfully."
else
    echo "WARNING: Sygic might not be in foreground. Relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup complete ==="