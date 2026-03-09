#!/bin/bash
# Setup script for Social Sharing Configuration task

echo "=== Setting up Social Sharing Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Reset Configuration to Defaults (Anti-Gaming)
# ==============================================================================
echo "Resetting configuration to known defaults..."

# We use the mysql CLI directly or via the helper to ensure a clean slate.
# sendfriend/email/enabled -> 0 (Disabled)
# sendfriend/email/allow_guest -> 1 (Default is usually Yes/1)
# sendfriend/email/max_recipients -> 5 (Default)
# sendfriend/email/max_per_hour -> 20 (Default)
# wishlist/email/number_limit -> 10 (Default)
# wishlist/email/email_identity -> general (Default)

RESET_QUERY="
DELETE FROM core_config_data WHERE path IN (
    'sendfriend/email/enabled',
    'sendfriend/email/allow_guest',
    'sendfriend/email/max_recipients',
    'sendfriend/email/max_per_hour',
    'wishlist/email/number_limit',
    'wishlist/email/email_identity'
);
INSERT INTO core_config_data (scope, scope_id, path, value) VALUES
('default', 0, 'sendfriend/email/enabled', '0'),
('default', 0, 'sendfriend/email/allow_guest', '1'),
('default', 0, 'sendfriend/email/max_recipients', '5'),
('default', 0, 'sendfriend/email/max_per_hour', '20'),
('default', 0, 'wishlist/email/number_limit', '10'),
('default', 0, 'wishlist/email/email_identity', 'general');
"

magento_query_headers "$RESET_QUERY"

# Clear cache to ensure admin sees fresh config
echo "Clearing config cache..."
cd /var/www/html/magento
php bin/magento cache:clean config > /dev/null 2>&1

# ==============================================================================
# 2. Ensure Admin Interface is Ready
# ==============================================================================
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we need to login
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 8
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Social Sharing Config Task Setup Complete ==="
echo "Configuration has been reset to defaults."
echo "Navigate to Stores > Configuration to begin."