#!/system/bin/sh
# Setup for send_chat_message task
# Runs on Android environment

echo "=== Setting up send_chat_message task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Ensure directories exist
mkdir -p /sdcard/tasks/send_chat_message

# Run the login helper to ensure we're logged in and on the Friends page
# This script handles app launch, login, and navigation to home
if [ -f "/sdcard/scripts/login_helper.sh" ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "ERROR: login_helper.sh not found!"
    exit 1
fi

# Wait for UI to settle
sleep 3

# Dismiss any keyboard that might be showing (just in case)
input keyevent 4 # KEYCODE_BACK
sleep 1

# Dump initial UI state for baseline comparison
uiautomator dump /sdcard/initial_ui_state.xml 2>/dev/null

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial_state.png 2>/dev/null

echo "=== send_chat_message setup complete ==="
echo "App is on the Friends page. Agent should navigate to chat and send the specified message."