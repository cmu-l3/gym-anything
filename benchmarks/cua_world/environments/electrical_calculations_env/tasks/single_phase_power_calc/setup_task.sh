#!/system/bin/sh
# Setup script for single_phase_power_calc task
# Runs on Android device

echo "=== Setting up Single Phase Power task ==="

PACKAGE="com.hsn.electricalcalculations"

# 1. Record task start time (using date +%s if available, else touch a marker file)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || touch /sdcard/task_start_marker

# 2. Clean up previous artifacts
rm -f /sdcard/power_analysis.txt
rm -f /sdcard/task_result.json

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch app to main menu
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Dismiss potential ads/dialogs
# Press Back once in case of an ad overlay
input keyevent KEYCODE_BACK
sleep 1

# Check if we accidentally exited (if back was pressed on main menu)
# Relaunch if needed
if dumpsys window | grep mCurrentFocus | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 6. Scroll to top of main menu to ensure consistent starting state
# Swipe down (simulates scrolling up)
input swipe 500 500 500 1500 500
sleep 1

echo "=== Setup Complete ==="