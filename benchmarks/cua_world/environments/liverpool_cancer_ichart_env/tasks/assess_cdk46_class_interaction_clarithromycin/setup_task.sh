#!/system/bin/sh
# Setup script for CDK4/6 Class Audit task
# Runs on Android device

echo "=== Setting up CDK4/6 Class Audit Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Record Task Start Time (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 2. Clear any previous results
rm -f /sdcard/cdk46_class_audit.txt
rm -f /sdcard/task_result.json

# 3. Ensure clean state for the app
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch App to ensure it's running but needs navigation
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Ensure we are at the Home/Welcome screen (press Back a few times just in case, then Home, then launch)
input keyevent KEYCODE_HOME
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# 6. Take initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="