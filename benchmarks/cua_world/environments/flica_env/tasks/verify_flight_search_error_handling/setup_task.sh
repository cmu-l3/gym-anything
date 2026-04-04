#!/system/bin/sh
echo "=== Setting up Flight Search Error Handling Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous task artifacts
rm -f /sdcard/Documents/flight_search_report.txt
mkdir -p /sdcard/Documents

# 3. Ensure App is Running and Logged In
# We use the helper script to handle login/navigation to home
if [ -f "/sdcard/scripts/login_helper.sh" ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "ERROR: Login helper script not found!"
    exit 1
fi

# 4. Clear any existing tracked flights (simulated by ensuring we start fresh)
# Since we can't easily programmatically clear specific items without complex UI automation,
# we rely on the agent to ignore existing items or the login helper to reset state.
# The login helper force-stops the app, which clears transient state.

echo "=== Task Setup Complete ==="
echo "App is ready on Friends/Home screen."
echo "Report file cleaned."