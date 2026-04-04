#!/bin/bash
# Setup script for Session Persistence Configuration task

echo "=== Setting up Session Persistence Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# Reset Configuration to "Bad" State
# ==============================================================================
# We set values to something incorrect so we can verify the agent actually changes them.
# 1. Set Cookie Lifetime to 86400 (24 hours) - Agent needs to change to 3600
# 2. Disable Persistence - Agent needs to enable it
# 3. Set Persistence Lifetime to 31536000 (1 year) - Agent needs to change to 2592000
echo "Resetting configuration to initial state..."

# Helper to set config via CLI (faster/safer than UI for setup)
set_config() {
    local path="$1"
    local value="$2"
    php /var/www/html/magento/bin/magento config:set "$path" "$value" --lock-env
}

# Apply initial "wrong" settings
cd /var/www/html/magento
php bin/magento config:set web/cookie/cookie_lifetime 86400
php bin/magento config:set persistent/options/enabled 0
php bin/magento config:set persistent/options/lifetime 31536000
php bin/magento config:set persistent/options/remember_enabled 0
php bin/magento config:set persistent/options/remember_default 0
php bin/magento config:set persistent/options/logout_clear 1
php bin/magento config:set persistent/options/shopping_cart 0

# Clear cache to ensure settings apply
php bin/magento cache:clean config

# ==============================================================================
# Browser Setup
# ==============================================================================

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Handle login if needed
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
echo "Values have been reset to incorrect defaults."