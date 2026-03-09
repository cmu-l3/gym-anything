#!/system/bin/sh
echo "=== Setting up check_beta_blocker_with_osimertinib task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks/check_beta_blocker_with_osimertinib"

# 1. Clean up previous artifacts
rm -f /sdcard/answer.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/task_start_time.txt

# 2. Record start time (using date +%s)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 1

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch app fresh
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Verify launch
if pidof com.liverpooluni.ichartoncology > /dev/null; then
    echo "App launched successfully."
else
    echo "WARNING: App did not launch, trying again..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
fi

echo "=== Setup complete ==="