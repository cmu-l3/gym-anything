#!/system/bin/sh
echo "=== Setting up Capecitabine Audit Task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Clean state: Force stop the app to ensure we start from scratch
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 2. Return to Home screen
echo "Going to Home screen..."
input keyevent KEYCODE_HOME
sleep 1

# 3. Clean up previous artifacts
rm -f /sdcard/Download/capecitabine_audit.txt
rm -f /sdcard/task_result.json

# 4. Record start time (using file modification time as marker)
touch /sdcard/task_start_marker
echo "Task start marker created."

# 5. Ensure screen is on and unlocked (basic Android keepalive)
input keyevent KEYCODE_WAKEUP
input keyevent 82 # KEYCODE_MENU/UNLOCK if needed

# 6. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== Setup Complete ==="