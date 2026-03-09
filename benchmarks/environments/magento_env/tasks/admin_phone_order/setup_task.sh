#!/bin/bash
# Setup script for Admin Phone Order task

echo "=== Setting up Admin Phone Order Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (orders must be created after this)
date +%s > /tmp/task_start_time.txt

# Record initial order count
echo "Recording initial order count..."
INITIAL_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count
echo "Initial order count: $INITIAL_COUNT"

# Ensure Customer Alice Williams exists (seed if missing)
echo "Checking for customer Alice Williams..."
CUSTOMER=$(get_customer_by_email "alice.williams@example.com")
if [ -z "$CUSTOMER" ]; then
    echo "Creating customer Alice Williams..."
    # Create via SQL directly if not exists to ensure consistent starting state
    magento_query "INSERT INTO customer_entity (website_id, email, group_id, store_id, created_at, firstname, lastname, is_active) VALUES (1, 'alice.williams@example.com', 1, 1, NOW(), 'Alice', 'Williams', 1);"
fi

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin/sales/order_create/"

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

# Handle Login if redirected
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard" && ! echo "$WINDOW_TITLE" | grep -qi "new order"; then
    echo "Detected login page - attempting to log in..."
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

echo "=== Admin Phone Order Task Setup Complete ==="
echo "Customer: Alice Williams (alice.williams@example.com)"
echo "Admin Credentials: admin / Admin1234!"