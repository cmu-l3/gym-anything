#!/system/bin/sh
echo "=== Setting up Ibrutinib AFib Safety Task ==="

# 1. timestamp for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous results
rm -f /sdcard/ibrutinib_afib_safety.txt
rm -f /sdcard/task_result.json

# 3. Ensure app is closed to start from a clean state
am force-stop com.liverpooluni.ichartoncology

# 4. Return to home screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME

echo "=== Setup complete ==="