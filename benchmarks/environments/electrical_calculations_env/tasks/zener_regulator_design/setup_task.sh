#!/system/bin/sh
echo "=== Setting up Zener Regulator Design Task ==="

# 1. Create task directory
mkdir -p /sdcard/tasks/zener_design
rm -f /sdcard/tasks/zener_design/result.txt

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/zener_design/start_time.txt

# 3. Ensure clean state for the app
PACKAGE="com.hsn.electricalcalculations"
am force-stop $PACKAGE
sleep 1

# 4. Launch the application to the main menu
echo "Launching Electrical Calculations app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Dismiss any potential startup dialogs/ads
input keyevent KEYCODE_BACK
sleep 1

# 6. Take initial screenshot (evidence of start state)
screencap -p /sdcard/tasks/zener_design/initial_state.png

echo "=== Setup Complete ==="