#!/system/bin/sh
echo "=== Setting up test_offline_mode_handling task ==="

# 1. Ensure Wi-Fi is ENABLED initially
echo "Ensuring Wi-Fi is enabled..."
svc wifi enable
sleep 3

# Verify connectivity (simple ping)
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Network is online."
else
    echo "WARNING: Network appears offline initially."
    # Try one more time
    svc wifi enable
    sleep 5
fi

# 2. Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 3. Clean up any previous reports
rm -f /sdcard/offline_test_report.txt

# 4. Launch App and ensure Logged In state
# Using the environment's login helper
sh /sdcard/scripts/login_helper.sh

# 5. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="