#!/bin/bash
# Setup script for fulfill_customer_order task
echo "=== Setting up fulfill_customer_order ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Ensure all services are running
ensure_services_running 120

# Verify customer janesmith exists (uid=3)
CUSTOMER_CHECK=$(drupal_db_query "SELECT uid, name FROM users_field_data WHERE name='janesmith'")
if [ -z "$CUSTOMER_CHECK" ]; then
    echo "ERROR: Customer janesmith not found!"
    exit 1
fi
echo "Customer verified: $CUSTOMER_CHECK"

# Verify required products exist
SONY_CHECK=$(drupal_db_query "SELECT variation_id, sku, price__number FROM commerce_product_variation_field_data WHERE sku='SONY-WH1000XM5'")
LOGI_CHECK=$(drupal_db_query "SELECT variation_id, sku, price__number FROM commerce_product_variation_field_data WHERE sku='LOGI-MXM3S'")
echo "Sony product: $SONY_CHECK"
echo "Logitech product: $LOGI_CHECK"

# Verify WELCOME10 coupon exists
COUPON_CHECK=$(drupal_db_query "SELECT id, code, status FROM commerce_promotion_coupon WHERE code='WELCOME10'")
echo "Coupon: $COUPON_CHECK"

# Record baseline state
INITIAL_ORDER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order")
INITIAL_ORDER_COUNT=${INITIAL_ORDER_COUNT:-0}
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count

INITIAL_ORDER_ITEM_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order_item")
INITIAL_ORDER_ITEM_COUNT=${INITIAL_ORDER_ITEM_COUNT:-0}
echo "$INITIAL_ORDER_ITEM_COUNT" > /tmp/initial_order_item_count

# Record initial coupon usage
INITIAL_COUPON_USAGE=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_usage WHERE promotion_id=1")
INITIAL_COUPON_USAGE=${INITIAL_COUPON_USAGE:-0}
echo "$INITIAL_COUPON_USAGE" > /tmp/initial_coupon_usage

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Commerce orders admin
navigate_firefox_to "http://localhost/admin/commerce/orders"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
