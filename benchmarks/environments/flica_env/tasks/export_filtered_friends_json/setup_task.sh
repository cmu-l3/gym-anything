#!/system/bin/sh
# Setup script for export_filtered_friends_json task

echo "=== Setting up export_filtered_friends_json task ==="

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Cleanup previous runs
rm -f /sdcard/united_friends.json
rm -f /sdcard/task_result.json

# 3. Ensure App is running and logged in
# Use the common login helper to reach the Friends page
sh /sdcard/scripts/login_helper.sh

# 4. Wait for UI to settle
sleep 3

# 5. Capture initial state
screencap -p /sdcard/initial_state.png

echo "=== Task setup complete ==="
echo "Agent should now: Add 'Captain UAL' and 'Captain DAL', then export United friends to JSON."