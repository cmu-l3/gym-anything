#!/bin/bash
# Setup script for Bulk Product Quantity Rules task

echo "=== Setting up Bulk Product Quantity Rules Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
TARGET_SKU="TSHIRT-001"

# 1. Verify target product exists
echo "Verifying product $TARGET_SKU exists..."
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -z "$PRODUCT_ID" ]; then
    echo "ERROR: Target product $TARGET_SKU not found. Re-seeding might be required."
    # Optional: could attempt to create it here, but environment should have it.
else
    echo "Product found: ID $PRODUCT_ID"
    # Reset inventory to defaults to ensure a clean start
    echo "Resetting inventory settings for $TARGET_SKU..."
    magento_query_headers "UPDATE cataloginventory_stock_item SET min_sale_qty=1, max_sale_qty=10000, enable_qty_increments=0, qty_increments=1, use_config_min_sale_qty=1, use_config_max_sale_qty=1, use_config_enable_qty_increments=1, use_config_qty_increments=1 WHERE product_id=$PRODUCT_ID"
fi

# 2. Record initial state timestamp
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin/catalog/product/"

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

# 4. Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
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

echo "=== Task Setup Complete ==="
echo "Target Product: Classic Cotton T-Shirt (SKU: $TARGET_SKU)"