#!/system/bin/sh
# Setup script for logout_account@1
# Ensures app is logged in on the Friends page before the agent starts.

echo "=== Setting up logout_account task ==="

# 1. Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Run login helper to ensure we're logged in on Friends page
# This helper handles launching, logging in, and navigating to home
if [ -f /sdcard/scripts/login_helper.sh ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "ERROR: login_helper.sh not found!"
    exit 1
fi

# 3. Wait a moment for UI to settle
sleep 5

# 4. Verify we are actually on the Friends page (Initial State Check)
uiautomator dump /sdcard/setup_verify.xml > /dev/null 2>&1
sleep 1

ON_FRIENDS_PAGE="false"
if [ -f /sdcard/setup_verify.xml ]; then
    if cat /sdcard/setup_verify.xml | grep -q "Add New Friend"; then
        ON_FRIENDS_PAGE="true"
    elif cat /sdcard/setup_verify.xml | grep -q "Friends"; then
        ON_FRIENDS_PAGE="true"
    fi
fi

if [ "$ON_FRIENDS_PAGE" = "true" ]; then
    echo "SETUP OK: On Friends page"
else
    echo "WARNING: May not be on Friends page. Attempting one retry..."
    sh /sdcard/scripts/login_helper.sh
fi

# 5. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

# Cleanup setup artifacts
rm -f /sdcard/setup_verify.xml

echo "=== Logout task setup complete ==="