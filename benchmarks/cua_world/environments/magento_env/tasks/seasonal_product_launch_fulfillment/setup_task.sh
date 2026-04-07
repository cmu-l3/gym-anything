#!/bin/bash
# Setup script for Seasonal Product Launch & Fulfillment task

echo "=== Setting up Seasonal Product Launch & Fulfillment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial counts to detect if work was actually done
echo "Recording initial database counts..."

INITIAL_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE attribute_code='shirt_size' AND entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_PRODUCT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_LINK_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_link" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_COUPON_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule_coupon" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
INITIAL_INVOICE_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_invoice" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_SHIPMENT_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_shipment" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_ATTR_COUNT" > /tmp/initial_attr_count
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count
echo "$INITIAL_LINK_COUNT" > /tmp/initial_link_count
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count
echo "$INITIAL_COUPON_COUNT" > /tmp/initial_coupon_count
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count
echo "$INITIAL_INVOICE_COUNT" > /tmp/initial_invoice_count
echo "$INITIAL_SHIPMENT_COUNT" > /tmp/initial_shipment_count

echo "Initial counts: Attrs=$INITIAL_ATTR_COUNT Products=$INITIAL_PRODUCT_COUNT Links=$INITIAL_LINK_COUNT Rules=$INITIAL_RULE_COUNT Coupons=$INITIAL_COUPON_COUNT Orders=$INITIAL_ORDER_COUNT Invoices=$INITIAL_INVOICE_COUNT Shipments=$INITIAL_SHIPMENT_COUNT"

# Delete stale output files
rm -f /tmp/seasonal_launch_result.json 2>/dev/null || true

# Flush Magento cache and reindex to ensure clean state
echo "Flushing cache and reindexing..."
cd /var/www/html/magento
php bin/magento cache:flush 2>/dev/null || true
php bin/magento indexer:reindex 2>/dev/null || true

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

# Auto-login if needed
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

echo "=== Seasonal Product Launch & Fulfillment Task Setup Complete ==="
echo ""
echo "Goal: Create configurable product, cart price rule with coupon, place and fulfill an order"
echo "If not already logged in, use: admin / Admin1234!"
