#!/system/bin/sh
echo "=== Setting up Post-Op Screening Task ==="

# 1. timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Clear previous artifacts
rm -f /sdcard/postop_screen.txt
rm -f /sdcard/task_result.json

# 3. Ensure app is in a clean state (force stop)
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE
sleep 1

# 4. Launch app to home screen
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle potential "Disclaimer" or "Update" dialogs if they appear on fresh launch
# (Basic tap to dismiss typical center-screen dialogs if any - though environment setup usually handles this)
# input tap 540 1200 2>/dev/null || true

# 6. Verify app is running
if pidof com.liverpooluni.ichartoncology > /dev/null; then
    echo "App launched successfully."
else
    echo "ERROR: App failed to launch."
    # Try one more time
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 7. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="