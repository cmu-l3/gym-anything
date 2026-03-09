#!/system/bin/sh
# Setup script for wire_dc_resistance task
# Runs on Android device

echo "=== Setting up wire_dc_resistance task ==="

# 1. Define package
PACKAGE="com.hsn.electricalcalculations"

# 2. Record task start time for anti-gaming (file modification checks)
date +%s > /sdcard/task_start_time.txt

# 3. Clean up previous artifacts
rm -f /sdcard/task_result.png
rm -f /sdcard/task_result.json

# 4. Ensure clean state: Force stop app
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 1

# 5. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 6. Launch App to warm it up, then go back to home
# This ensures the app is ready but the agent starts from a neutral state (Home Screen)
echo "Warming up app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5
# Dismiss potential "Rate Us" or ads by pressing back
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_HOME
sleep 1

# 7. Final check - verify we are at home screen (optional, mostly for logging)
dumpsys window | grep mCurrentFocus

echo "=== Setup Complete ==="