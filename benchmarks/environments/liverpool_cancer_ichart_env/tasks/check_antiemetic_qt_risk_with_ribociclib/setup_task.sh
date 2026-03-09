#!/system/bin/sh
set -e
echo "=== Setting up check_antiemetic_qt_risk_with_ribociclib task ==="

# 1. Record task start time
# Using date +%s if available, otherwise touching a file
date +%s > /sdcard/task_start_time.txt 2>/dev/null || touch /sdcard/task_start_marker

# 2. Clean up previous artifacts
rm -f /sdcard/interaction_result.txt
rm -f /sdcard/task_result.json

# 3. Ensure app is closed for a fresh start
am force-stop com.liverpooluni.ichartoncology 2>/dev/null || true
sleep 1

# 4. Go to Home screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 1

# 5. Take initial state screenshot
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="