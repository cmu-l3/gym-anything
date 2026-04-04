#!/system/bin/sh
# Setup script for select_safer_muscle_relaxant_rucaparib task
# Runs on Android via adb shell

echo "=== Setting up Muscle Relaxant Safety Task ==="

# 1. timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Cleanup previous runs
rm -f /sdcard/muscle_relaxant_safety.txt

# 3. Ensure App is in known state (Force stop and launch)
PACKAGE="com.liverpooluni.ichartoncology"
echo "Force stopping $PACKAGE..."
am force-stop $PACKAGE
sleep 1

echo "Launching app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 5

# 4. Capture initial state
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="