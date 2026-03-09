#!/system/bin/sh
echo "=== Setting up Investigate Analgesic Failure Task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up any previous results
rm -f /sdcard/abiraterone_pain_audit.txt

# Ensure the app is closed to start from a clean state
am force-stop com.liverpooluni.ichartoncology
sleep 2

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="