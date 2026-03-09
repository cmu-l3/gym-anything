#!/system/bin/sh
echo "=== Setting up Motor Slip Task ==="

# Ensure directory exists
mkdir -p /sdcard/tasks
mkdir -p /sdcard/scripts

# Record task start time (for anti-gaming verification)
date +%s > /sdcard/tasks/task_start_time.txt

# Remove previous result file to ensure fresh creation
rm -f /sdcard/tasks/motor_slip_result.txt

# Package name
PACKAGE="com.hsn.electricalcalculations"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Launch the app to the main screen
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss any potential initial dialogs/ads with Back key
input keyevent KEYCODE_BACK
sleep 2

# Ensure we are not on home screen (re-launch if needed)
# In Android shell, grepping dumpsys can be noisy, so we just blindly ensure launch
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# Take initial screenshot for evidence
screencap -p /sdcard/tasks/initial_state.png

echo "=== Task setup complete ==="