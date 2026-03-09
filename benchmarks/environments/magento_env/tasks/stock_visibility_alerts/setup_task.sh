#!/bin/bash
# Setup script for Stock Visibility & Alerts task

echo "=== Setting up Stock Visibility & Alerts Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
MAGENTO_ADMIN_URL="http://localhost/admin"

# 1. Reset configuration to default state to ensure clean start
# We want to ensure OOS is hidden (0) and alerts are off (0) initially
echo "Resetting configuration to defaults..."
magento_query "DELETE FROM core_config_data WHERE path IN (
    'cataloginventory/options/show_out_of_stock',
    'cataloginventory/options/stock_threshold_qty',
    'catalog/productalert/allow_stock',
    'catalog/productalert/allow_price',
    'catalog/productalert/email_stock_identity'
);" 2>/dev/null

# Flush cache to apply DB changes
echo "Flushing cache..."
php /var/www/html/magento/bin/magento cache:clean config 2>/dev/null || true

# 2. Record initial timestamp
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
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

# 4. Handle Login if needed
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
    sleep 0.1
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    echo "Waiting for dashboard..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to:"
echo "1. Stores > Configuration > Catalog > Inventory (for visibility)"
echo "2. Stores > Configuration > Catalog > Catalog > Product Alerts (for alerts)"