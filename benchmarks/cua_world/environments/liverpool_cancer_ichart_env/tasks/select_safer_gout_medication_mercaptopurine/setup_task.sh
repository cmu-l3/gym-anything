#!/system/bin/sh
echo "=== Setting up Gout Medication Safety Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Force stop the app to ensure clean state
am force-stop $PACKAGE
sleep 1

# 2. Clean up previous artifacts
rm -f /sdcard/gout_safety_check.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# 3. Record start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch app to ensure it's ready (optional, but good for stability)
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 5

# 6. Check if we need to accept any crash dialogs or warm up
# (The environment setup script handles the DB download, so we assume it's ready)

# 7. Force stop again so the agent starts from "launching the app"
am force-stop $PACKAGE
sleep 1
input keyevent KEYCODE_HOME

echo "=== Setup Complete ==="