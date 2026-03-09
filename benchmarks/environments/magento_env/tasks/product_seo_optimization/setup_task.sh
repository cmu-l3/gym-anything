#!/bin/bash
# Setup script for Product SEO Optimization task

echo "=== Setting up Product SEO Optimization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # If firefox is running, ensure it's at the admin panel
    echo "Firefox already running, checking URL..."
    # We can't easily check URL, so we assume or open new tab if needed, 
    # but strictly following the pattern, we just focus it.
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

    # Click in the window to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5

    # Tab to first field and type username
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.1
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5

    # Tab to password field
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5

    # Press Enter to submit
    DISPLAY=:1 xdotool key Return

    # Wait for dashboard to load
    echo "Waiting for dashboard to load..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Record initial URL key for the product (to verify it changed later)
TARGET_SKU="LAPTOP-001"
INITIAL_URL_KEY=$(magento_query "SELECT v.value FROM catalog_product_entity e
    JOIN catalog_product_entity_varchar v ON e.entity_id = v.entity_id
    WHERE e.sku = '$TARGET_SKU'
    AND v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='url_key' AND entity_type_id=4)
    AND v.store_id = 0 LIMIT 1" 2>/dev/null)
echo "$INITIAL_URL_KEY" > /tmp/initial_url_key.txt

echo "=== Setup Complete ==="
echo ""
echo "Task: Update SEO properties for Product SKU: $TARGET_SKU"
echo "If not logged in, use: $ADMIN_USER / $ADMIN_PASS"
echo ""