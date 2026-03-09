#!/system/bin/sh
echo "=== Setting up HIV-Crizotinib Safety Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
RESULT_FILE="/sdcard/crizotinib_hiv_safety.txt"

# 1. Clean up previous artifacts
rm -f "$RESULT_FILE"
rm -f /sdcard/task_result.json

# 2. Record task start time
date +%s > /sdcard/task_start_time.txt

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch app to home screen
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Handle potential first-run dialogs (though env setup should have handled this)
# Just in case, try to tap "OK" coordinates for the download dialog if it appears
# This is a safety measure; usually the base env is ready.
# input tap 815 1403 
# sleep 2

# 6. Verify app is running
if pidof com.liverpooluni.ichartoncology > /dev/null; then
    echo "App is running."
else
    echo "ERROR: App failed to start."
    # Try one more time
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup complete ==="