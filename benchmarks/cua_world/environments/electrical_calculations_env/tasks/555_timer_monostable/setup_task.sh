#!/system/bin/sh
set -e
echo "=== Setting up 555 Timer Monostable task ==="

# 1. Create task directory
mkdir -p /sdcard/tasks/555_timer_monostable

# 2. Clean up previous artifacts
rm -f /sdcard/tasks/555_timer_monostable/result.txt
rm -f /sdcard/task_result.json

# 3. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 4. Ensure clean app state
# Force stop the app to ensure we start from a known state (not halfway through a previous calculation)
am force-stop com.hsn.electricalcalculations 2>/dev/null || true
sleep 1

# 5. Go to home screen
input keyevent KEYCODE_HOME
sleep 2

# 6. Launch the app using robust helper
echo "Launching Electrical Calculations..."
. /sdcard/scripts/launch_helper.sh
launch_electrical_calc

# 7. Capture initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="