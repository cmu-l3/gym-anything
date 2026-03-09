#!/bin/bash
# Setup script for Product Relationships task

echo "=== Setting up Product Relationships Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
MAIN_SKU="LAPTOP-001"

# 1. Clear existing links for LAPTOP-001 to ensure a clean start
echo "Clearing existing product links for $MAIN_SKU..."

# Get entity_id for LAPTOP-001
MAIN_PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$MAIN_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -n "$MAIN_PRODUCT_ID" ]; then
    echo "Found product ID: $MAIN_PRODUCT_ID. Removing existing links..."
    magento_query "DELETE FROM catalog_product_link WHERE product_id=$MAIN_PRODUCT_ID"
else
    echo "WARNING: Product $MAIN_SKU not found during setup!"
fi

# Record initial link count (should be 0 now)
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_link WHERE product_id='$MAIN_PRODUCT_ID'" 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "${INITIAL_COUNT:-0}" > /tmp/initial_link_count
echo "Initial link count: ${INITIAL_COUNT:-0}"

# 2. Ensure Firefox is running and focused on Magento admin
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

# 3. Handle Login if needed
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
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Product Relationships Task Setup Complete ==="
echo ""
echo "Target Product: Business Laptop Pro (SKU: $MAIN_SKU)"
echo "If not already logged in, use: admin / Admin1234!"
echo ""