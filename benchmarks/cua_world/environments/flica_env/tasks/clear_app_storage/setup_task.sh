#!/system/bin/sh
# Setup script for clear_app_storage task
# Ensures Flight Crew View is logged in and on the Friends page before agent starts

echo "=== Setting up clear_app_storage task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Ensure we have the helper script
if [ ! -f "/sdcard/scripts/login_helper.sh" ]; then
    echo "ERROR: Login helper script not found!"
    exit 1
fi

# Run the login helper to get to the Friends page (state with data to clear)
echo "Ensuring app is logged in..."
sh /sdcard/scripts/login_helper.sh

# Verify we are actually logged in by dumping UI
echo "Verifying initial state..."
sleep 2
uiautomator dump /sdcard/initial_state.xml 2>/dev/null

# Check if Friends page is visible (simple grep check)
if grep -q "Friends" /sdcard/initial_state.xml || grep -q "Add New Friend" /sdcard/initial_state.xml; then
    echo "Initial state verified: App is logged in."
else
    echo "WARNING: App might not be fully logged in. Proceeding anyway."
fi

# Take initial screenshot for evidence
screencap -p /sdcard/initial_screenshot.png
echo "Initial screenshot saved."

echo "=== Task setup completed ==="
echo "Agent must now navigate to Settings to clear app data."