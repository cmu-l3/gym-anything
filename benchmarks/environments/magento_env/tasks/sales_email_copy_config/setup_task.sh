#!/bin/bash
# Setup script for Sales Email Copy Config task

echo "=== Setting up Sales Email Copy Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Reset configuration to default state (clear specific paths)
# This ensures the agent must actually perform the task
echo "Resetting sales email configuration..."
magento_query "DELETE FROM core_config_data WHERE path IN ('sales_email/order/copy_to', 'sales_email/order/copy_method', 'sales_email/invoice/copy_to', 'sales_email/invoice/copy_method')" 2>/dev/null

# Clear cache to ensure settings apply (though admin panel reads from DB usually)
# We do this to ensure UI reflects the DB state
php /var/www/html/magento/bin/magento cache:clean config 2>/dev/null || true

# 2. Record initial state (should be empty/default)
echo "Recording initial state..."
INITIAL_STATE=$(magento_query "SELECT path, value FROM core_config_data WHERE path LIKE 'sales_email/%/copy_%'" 2>/dev/null || echo "None")
echo "$INITIAL_STATE" > /tmp/initial_config_state.txt
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

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

# 4. Check if login is needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
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
    
    # Wait for dashboard
    echo "Waiting for dashboard..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to Stores > Configuration > Sales > Sales Emails"