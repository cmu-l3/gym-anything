#!/system/bin/sh
# Setup script for cctv_storage_calc
# Runs on Android device

echo "=== Setting up CCTV Storage Task ==="

# Define paths
TASK_DIR="/sdcard/tasks/cctv_storage_calc"
RESULT_FILE="/sdcard/cctv_storage_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Clean up previous artifacts
rm -f "$RESULT_FILE"
rm -f "$START_TIME_FILE"
rm -f /sdcard/task_final.png
rm -f /sdcard/task_result.json

# Record start time
date +%s > "$START_TIME_FILE"

# Ensure clean app state
PACKAGE="com.hsn.electricalcalculations"
am force-stop $PACKAGE
sleep 1

# Launch App
echo "Launching app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Handle potential "Rate Us" or Ad popups by sending BACK key once
input keyevent KEYCODE_BACK
sleep 1

# If we exited the app (because there was no popup), relaunch
if ! dumpsys window | grep -q "$PACKAGE"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

# Go to top of main menu (scroll up)
input swipe 500 500 500 1500 300
sleep 1

echo "=== Setup Complete ==="