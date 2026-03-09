#!/bin/bash
# Setup script for Store Operations Config task

echo "=== Setting up Store Operations Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Configuration to known "wrong" state to ensure agent makes changes
# We use magento config:set via bin/magento inside the container or direct DB updates
# Direct DB updates are faster for setup scripts

echo "Resetting configuration to default/opposing states..."

# Persistent Cart: Disable it, set lifetime to 1 year (31536000), Remember Me: No
magento_query "UPDATE core_config_data SET value='0' WHERE path='persistent/options/enabled';"
magento_query "UPDATE core_config_data SET value='31536000' WHERE path='persistent/options/lifetime';"
magento_query "UPDATE core_config_data SET value='0' WHERE path='persistent/options/remember_enabled';"
magento_query "UPDATE core_config_data SET value='1' WHERE path='persistent/options/logout_clear';" # Set to Yes (wrong)

# Newsletter: Disable Guest Subscription
magento_query "UPDATE core_config_data SET value='0' WHERE path='newsletter/subscription/allow_guest_subscribe';"

# Contact Us: Set to default admin email
magento_query "UPDATE core_config_data SET value='hello@example.com' WHERE path='contact/email/recipient_email';"

# Wishlist: Enable it
magento_query "UPDATE core_config_data SET value='1' WHERE path='wishlist/general/active';"

# Clear cache to ensure DB changes are picked up if we were using the app (though we are about to launch it)
# Running cache:clean in container
docker exec -u www-data magento-web php bin/magento cache:clean config > /dev/null 2>&1

# 2. Launch Firefox and login
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Auto-login if on login page
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Update Store Configuration"
echo "  - Persistent Cart: Enabled, 30 days (calculate seconds), Remember Me: Yes"
echo "  - Newsletter: Allow Guest Subscription"
echo "  - Contact Us: Email to support@luma.com"
echo "  - Wishlist: Disabled"
echo ""