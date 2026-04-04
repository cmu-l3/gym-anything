#!/system/bin/sh
echo "=== Setting up Air Core Inductor Design Task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Remove any previous result file
rm -f /sdcard/inductor_result.txt

# Package name
PACKAGE="com.hsn.electricalcalculations"

# Force stop to ensure clean state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# Ensure we are at home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch the application
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Dismiss any potential startup dialogs/ads by pressing back once (carefully)
# or just wait a bit longer. We'll wait.
sleep 3

# Check if app is running
if pidof com.hsn.electricalcalculations > /dev/null; then
    echo "App launched successfully."
else
    echo "WARNING: App process not found."
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="