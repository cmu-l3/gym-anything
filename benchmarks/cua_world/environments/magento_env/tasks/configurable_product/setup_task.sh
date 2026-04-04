#!/bin/bash
# Setup script for Configurable Product task

echo "=== Setting up Configurable Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial counts to detect if work was actually done
echo "Recording initial database counts..."

# Count existing attributes with this code (should be 0)
INITIAL_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE attribute_code='shirt_color' AND entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Count existing products
INITIAL_PRODUCT_COUNT=$(get_product_count 2>/dev/null || echo "0")

# Count existing links between configurable and simple products
INITIAL_LINK_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_link" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_ATTR_COUNT" > /tmp/initial_attr_count
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count
echo "$INITIAL_LINK_COUNT" > /tmp/initial_link_count

echo "Initial counts: Attributes=$INITIAL_ATTR_COUNT, Products=$INITIAL_PRODUCT_COUNT, Links=$INITIAL_LINK_COUNT"

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

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

# Check if we're on the login page (window title contains "login" or we need to log in)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

# Auto-login if needed
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
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

echo "=== Configurable Product Task Setup Complete ==="
echo ""
echo "Goal: Create attribute 'Shirt Color' and a Configurable Product 'Oxford Dress Shirt'"
echo "If not already logged in, use: admin / Admin1234!"