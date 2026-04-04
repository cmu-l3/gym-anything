#!/system/bin/sh
echo "=== Setting up screen_antibiotic_safety_methotrexate task ==="

# 1. timestamp for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/mtx_antibiotic_screen.txt
rm -f /sdcard/task_result.json

# 3. Ensure app is in a clean state (not running)
am force-stop com.liverpooluni.ichartoncology
sleep 1

# 4. Go to home screen to ensure neutral starting state
input keyevent KEYCODE_HOME
sleep 2

# 5. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="