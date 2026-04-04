#!/system/bin/sh
# Setup script for record_subsoiling_tillage task
# Runs on Android device via adb shell

echo "=== Setting up Subsoiling Task ==="

PACKAGE="org.farmos.app"

# 1. Reset App State (Clean Slate)
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE

# 2. Grant Permissions
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION

# 3. Launch App
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1

# 4. Wait for App to Load
sleep 5

# 5. Record Task Start Time
date +%s > /sdcard/task_start_time.txt

# 6. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="