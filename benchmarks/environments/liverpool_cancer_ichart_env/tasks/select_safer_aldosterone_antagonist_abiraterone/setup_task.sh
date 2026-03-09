#!/system/bin/sh
echo "=== Setting up select_safer_aldosterone_antagonist_abiraterone ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up previous results
rm -f /sdcard/safety_check.json

# Ensure app is closed (Starting State requirement)
am force-stop com.liverpooluni.ichartoncology
sleep 1

# Go to Home screen
input keyevent KEYCODE_HOME
sleep 2

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="