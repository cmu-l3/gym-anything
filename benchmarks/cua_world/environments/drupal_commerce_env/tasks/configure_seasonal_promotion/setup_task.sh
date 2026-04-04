#!/bin/bash
# Setup script for configure_seasonal_promotion task
echo "=== Setting up configure_seasonal_promotion ==="

. /workspace/scripts/task_utils.sh

if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

ensure_services_running 120

# Record baseline promotion and coupon counts
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
INITIAL_PROMO_COUNT=${INITIAL_PROMO_COUNT:-0}
echo "$INITIAL_PROMO_COUNT" > /tmp/initial_promo_count

INITIAL_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
INITIAL_COUPON_COUNT=${INITIAL_COUPON_COUNT:-0}
echo "$INITIAL_COUPON_COUNT" > /tmp/initial_coupon_count

# Record existing promotion IDs to distinguish new from old
drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data" > /tmp/initial_promo_ids

# Verify no promotion named 'Spring Clearance 30% Off' already exists
EXISTING=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data WHERE name LIKE '%Spring Clearance%'")
if [ "$EXISTING" -gt 0 ] 2>/dev/null; then
    echo "WARNING: A Spring Clearance promotion already exists, cleaning up..."
    drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%Spring Clearance%'"
fi

# Verify no SPRING30 coupon exists
EXISTING_COUPON=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon WHERE code='SPRING30'")
if [ "$EXISTING_COUPON" -gt 0 ] 2>/dev/null; then
    echo "WARNING: SPRING30 coupon exists, cleaning up..."
    drupal_db_query "DELETE FROM commerce_promotion_coupon WHERE code='SPRING30'"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Promotions admin
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
