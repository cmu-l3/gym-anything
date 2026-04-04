#!/bin/bash
# Setup script for Gift Message Workflow task

echo "=== Setting up Gift Message Workflow Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial order count
echo "Recording initial order count..."
INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count
echo "Initial order count: $INITIAL_ORDER_COUNT"

# Ensure Gift Messages are DISABLED initially (to ensure agent actually does the work)
echo "Ensuring Gift Messages are disabled initially..."
magento_query "UPDATE core_config_data SET value='0' WHERE path='sales/gift_options/allow_order'" 2>/dev/null
# Flush cache to ensure config takes effect
php /var/www/html/magento/bin/magento cache:clean config > /dev/null 2>&1

# Ensure Firefox is running and logged in to Admin
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

# Handle Admin Login if needed
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
echo "Task: Enable 'Gift Messages on Order Level' in config, then place an order with a message."
echo "Admin Credentials: admin / Admin1234!"
echo ""