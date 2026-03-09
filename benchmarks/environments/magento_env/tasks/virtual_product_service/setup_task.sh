#!/bin/bash
# Setup script for Virtual Product Service task

echo "=== Setting up Virtual Product Service Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial maximum product ID to verify new creation (anti-gaming)
echo "Recording initial max product ID..."
INITIAL_MAX_ID=$(magento_query "SELECT MAX(entity_id) FROM catalog_product_entity" 2>/dev/null | tail -1 | tr -d '[:space:]')
if [ -z "$INITIAL_MAX_ID" ] || [ "$INITIAL_MAX_ID" == "NULL" ]; then
    INITIAL_MAX_ID="0"
fi
echo "$INITIAL_MAX_ID" > /tmp/initial_max_product_id
echo "Initial max product ID: $INITIAL_MAX_ID"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and focused on Magento admin
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

# Check if we're on the login page (window title contains "login" or we need to log in)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

# If we detect we're on the login page (title contains "Admin" but not "Dashboard"), try to log in
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    
    # Click center to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5

    # Login flow
    DISPLAY=:1 xdotool key Tab
    sleep 0.2
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.2
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    
    # Wait for dashboard to load
    echo "Waiting for dashboard login..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: Create Virtual Product 'Professional Home Theater Installation' (SKU: SVC-HT-INSTALL)"