#!/system/bin/sh
# Setup script for cable_reel_capacity task
echo "=== Setting up Cable Reel Capacity Task ==="

# 1. Record Start Time (Anti-gaming)
date +%s > /sdcard/task_start_time.txt

# 2. Clean previous run artifacts
rm -f /sdcard/reel_capacity.txt
rm -f /sdcard/reel_capacity_evidence.png
rm -f /sdcard/task_result.json

# 3. Ensure App is in Clean State
PACKAGE="com.hsn.electricalcalculations"
echo "Force stopping app to ensure clean state..."
am force-stop $PACKAGE
sleep 2

# 4. Launch App to Home Screen
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 5

# 5. Dismiss any potential initial dialogs/ads
# (Press Back once just in case an ad appeared)
input keyevent KEYCODE_BACK
sleep 1

# 6. Ensure we are actually in the app (not home screen)
# If back button killed it, restart
if ! dumpsys window | grep -q "mCurrentFocus.*$PACKAGE"; then
    echo "Relaunching app..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    sleep 3
fi

# 7. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="