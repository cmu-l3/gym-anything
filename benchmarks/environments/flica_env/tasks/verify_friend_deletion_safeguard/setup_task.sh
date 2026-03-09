#!/system/bin/sh
echo "=== Setting up verify_friend_deletion_safeguard task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Ensure app is installed and permissions granted (handled by env setup, but good to be safe)
PACKAGE="com.robert.fcView"

# Use the helper to ensure we are logged in and on the Friends page
# This helper handles:
# - Launching the app
# - Logging in if necessary (cuasuite@gmail.com)
# - Navigating to the Friends (Home) page
echo "Running login helper..."
sh /sdcard/scripts/login_helper.sh

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="
echo "App is ready on Friends page."