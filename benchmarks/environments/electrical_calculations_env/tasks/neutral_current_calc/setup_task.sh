#!/system/bin/sh
# setup_neutral_current.sh
# Runs on Android device to prepare the environment

echo "=== Setting up Neutral Current Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up any previous task artifacts
rm -f /sdcard/neutral_current.txt
rm -f /sdcard/neutral_result.png
rm -f /sdcard/task_result.json
rm -f /sdcard/task_final.png

# 3. Ensure the app is in a clean state (restart it)
PACKAGE="com.hsn.electricalcalculations"
echo "Restarting application..."
am force-stop $PACKAGE
sleep 1

# Launch the app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 5

# 4. Take initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="