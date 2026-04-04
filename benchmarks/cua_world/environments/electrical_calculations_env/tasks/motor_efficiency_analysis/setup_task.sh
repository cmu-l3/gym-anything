#!/system/bin/sh
# Setup script for motor_efficiency_analysis task

echo "=== Setting up Motor Efficiency Analysis Task ==="

# 1. timestamp for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Cleanup previous runs
rm -f /sdcard/efficiency_report.txt 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

# 3. Ensure clean application state
PACKAGE="com.hsn.electricalcalculations"
echo "Force stopping $PACKAGE..."
am force-stop $PACKAGE
sleep 2

# 4. Launch Application
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Dismiss potential startup dialogs/ads
# Press Back once to clear overlays
input keyevent KEYCODE_BACK
sleep 1

# Ensure we are not on home screen (re-launch if needed)
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "Launcher"; then
    echo "Relaunching app to ensure foreground..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task Setup Complete ==="