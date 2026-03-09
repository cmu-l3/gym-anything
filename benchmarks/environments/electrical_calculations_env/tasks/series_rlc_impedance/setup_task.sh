#!/system/bin/sh
set -e
echo "=== Setting up series_rlc_impedance task ==="

# 1. Prepare Directory
mkdir -p /sdcard/tasks/series_rlc_impedance
rm -f /sdcard/tasks/series_rlc_impedance/result.txt

# 2. Record Task Start Time (for anti-gaming)
date +%s > /sdcard/tasks/series_rlc_impedance/start_time.txt

# 3. Clean App State
PACKAGE="com.hsn.electricalcalculations"
am force-stop $PACKAGE 2>/dev/null || true
sleep 1

# 4. Return to Home Screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 1

# 5. Capture Initial State Evidence
screencap -p /sdcard/tasks/series_rlc_impedance/initial_state.png

echo "=== Setup complete ==="