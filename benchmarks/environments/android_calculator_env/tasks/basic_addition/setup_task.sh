#!/system/bin/sh
# Setup script for basic_addition task
# This runs via: adb shell sh /sdcard/tasks/basic_addition/setup_task.sh

echo "=== Setting up basic_addition task ==="

# Make sure we're at home screen first
input keyevent KEYCODE_HOME
sleep 1

# Launch Calculator app (try YetCalc first, then AOSP)
echo "Launching Calculator app..."
am start -n yetzio.yetcalc/.MainActivity 2>/dev/null || am start -n com.android.calculator2/.Calculator 2>/dev/null
sleep 2

# Clear any previous calculation by pressing AC button
echo "Clearing calculator..."
input keyevent KEYCODE_CLEAR 2>/dev/null || input keyevent KEYCODE_C 2>/dev/null || input keyevent KEYCODE_DEL 2>/dev/null
sleep 1

echo "=== Task setup completed ==="
echo "Calculator is ready. Agent should now compute 25 + 17 = 42"
