#!/bin/bash
echo "=== Setting up Tax, Shipping, and Order Fulfillment Task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
echo "Recording initial state..."

INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/tax_shipping_order_initial_count

EXISTING_ORDER_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_type='shop_order' AND post_status != 'auto-draft'" 2>/dev/null)
echo "${EXISTING_ORDER_IDS:-}" > /tmp/tax_shipping_order_existing_ids

# Clean up: remove any existing CA tax rate
wc_query "DELETE FROM wp_woocommerce_tax_rates WHERE tax_rate_state='CA'" 2>/dev/null || true
echo "Cleared existing CA tax rates"

# Clean up: remove any existing 'California' shipping zone
CAL_ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE LOWER(zone_name)='california' LIMIT 1" 2>/dev/null)
if [ -n "$CAL_ZONE_ID" ]; then
    wc_query "DELETE FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$CAL_ZONE_ID" 2>/dev/null
    wc_query "DELETE FROM wp_woocommerce_shipping_zone_locations WHERE zone_id=$CAL_ZONE_ID" 2>/dev/null
    wc_query "DELETE FROM wp_woocommerce_shipping_zones WHERE zone_id=$CAL_ZONE_ID" 2>/dev/null
    echo "Removed pre-existing California shipping zone"
fi

# Disable taxes initially (agent must enable)
cd /var/www/html/wordpress 2>/dev/null || true
wp option update woocommerce_calc_taxes 'no' --allow-root 2>/dev/null || true
echo "Taxes disabled (agent must enable)"

# Record timestamp after cleanup
date +%s > /tmp/tax_shipping_order_start_ts

# Verify prerequisite products exist
echo "Verifying prerequisite products..."
OCT_DATA=$(get_product_by_sku "OCT-BLK-M" 2>/dev/null)
BCB_DATA=$(get_product_by_sku "BCB-SET2" 2>/dev/null)
echo "Organic Cotton T-Shirt (OCT-BLK-M): $([ -n "$OCT_DATA" ] && echo "FOUND" || echo "NOT FOUND")"
echo "Bamboo Cutting Board Set (BCB-SET2): $([ -n "$BCB_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

# Verify customer exists
CUSTOMER_DATA=$(get_customer_by_email "jane.smith@example.com" 2>/dev/null)
echo "Customer Jane Smith: $([ -n "$CUSTOMER_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

# Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/tax_shipping_order_start_screenshot.png

echo "=== Tax, Shipping, and Order Fulfillment Task Setup Complete ==="
