#!/system/bin/sh
echo "=== Setting up Audit Navigation Menu Task ==="

# 1. Clean up previous artifacts
rm -f /sdcard/menu_audit.txt
rm -f /sdcard/task_result.json

# 2. Record task start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is running and logged in
# We use the provided login helper to reach the "Friends" page (home)
sh /sdcard/scripts/login_helper.sh

# 4. Wait a moment for UI to settle
sleep 2

# 5. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="
echo "Task: Open navigation menu and list items to /sdcard/menu_audit.txt"