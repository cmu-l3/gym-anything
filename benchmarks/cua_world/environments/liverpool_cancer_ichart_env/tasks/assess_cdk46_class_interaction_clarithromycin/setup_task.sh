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

# 4. Launch App to ensure it's running
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart
sleep 1

# 6. Take initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="