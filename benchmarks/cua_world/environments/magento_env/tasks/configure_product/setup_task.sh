#!/bin/bash
# Setup script for Create Configurable Product task

echo "=== Setting up Configure Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial product counts
echo "Recording initial product counts..."
INITIAL_PRODUCT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_CONFIGURABLE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity WHERE type_id='configurable'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count
echo "${INITIAL_CONFIGURABLE_COUNT:-0}" > /tmp/initial_configurable_count
echo "Initial product count: $INITIAL_PRODUCT_COUNT, configurable: ${INITIAL_CONFIGURABLE_COUNT:-0}"

# Record Sports category ID (seeded by setup_magento.sh)
SPORTS_CAT_ID=$(magento_query "SELECT cce.entity_id FROM catalog_category_entity cce JOIN catalog_category_entity_varchar ccev ON cce.entity_id=ccev.entity_id WHERE LOWER(TRIM(ccev.value))='sports' AND ccev.attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3) AND ccev.store_id=0 LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${SPORTS_CAT_ID:-0}" > /tmp/sports_category_id
echo "Sports category ID: ${SPORTS_CAT_ID:-not found}"

# Record Color attribute ID for catalog_product
COLOR_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='color' AND entity_type_id=(SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code='catalog_product') LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${COLOR_ATTR_ID:-0}" > /tmp/color_attribute_id
echo "Color attribute ID: ${COLOR_ATTR_ID:-not found}"

# Ensure Firefox is running and admin is logged in
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

# Check if login is needed
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
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    echo "Waiting for dashboard..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Configure Product Task Setup Complete ==="
echo ""
echo "Magento Admin: http://localhost/admin"
echo "Credentials: admin / Admin1234!"
echo ""
