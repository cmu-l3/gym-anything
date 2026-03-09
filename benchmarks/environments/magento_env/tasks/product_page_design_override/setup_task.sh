#!/bin/bash
# Setup script for Product Page Design Override task

echo "=== Setting up Product Page Design Override Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state for LAPTOP-001
echo "Recording initial product state..."
# Get entity_id for LAPTOP-001
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='LAPTOP-001'" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -z "$PRODUCT_ID" ]; then
    echo "ERROR: Product LAPTOP-001 not found!"
    exit 1
fi

echo "Target Product ID: $PRODUCT_ID"

# Get initial layout
INITIAL_LAYOUT=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='page_layout' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)
# Get initial container
INITIAL_CONTAINER=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='options_container' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)

echo "$INITIAL_LAYOUT" > /tmp/initial_layout.txt
echo "$INITIAL_CONTAINER" > /tmp/initial_container.txt
echo "Initial State - Layout: ${INITIAL_LAYOUT:-default}, Container: ${INITIAL_CONTAINER:-default}"

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

# Check login state (basic check)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
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

echo "=== Task Setup Complete ==="
echo "Target Product: Business Laptop Pro (SKU: LAPTOP-001)"
echo "Goal: Set Layout to '1 column' and Product Options to 'Product Info Column'"