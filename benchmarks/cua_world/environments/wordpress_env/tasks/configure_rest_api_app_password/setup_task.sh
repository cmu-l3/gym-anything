#!/bin/bash
# Setup script for configure_rest_api_app_password task (pre_task hook)

echo "=== Setting up REST API Configuration task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Clean up any potential artifacts from previous runs
echo "Cleaning up any existing artifacts..."
cd /var/www/html/wordpress

# Delete any existing posts with the target title
wp_db_query "DELETE FROM wp_posts WHERE post_title='App Configuration Endpoint'" 2>/dev/null || true

# Delete any existing Application Password with the target name for admin (user_id=1)
# Note: Application Passwords are stored in wp_usermeta under '_application_passwords'
wp_db_query "DELETE FROM wp_usermeta WHERE user_id=1 AND meta_key='_application_passwords'" 2>/dev/null || true

# Remove target credentials file if it exists
rm -f /home/ga/mobile_api_credentials.txt

# Ensure Firefox is running and focused on WordPress admin profile page
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    # Launch straight into the admin dashboard
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="