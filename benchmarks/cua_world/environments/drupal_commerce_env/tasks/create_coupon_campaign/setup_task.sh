#!/bin/bash
# Setup script for Create Coupon Campaign task

echo "=== Setting up Create Coupon Campaign Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for DB query if not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 90

# Clean up any existing data from previous runs to ensure a clean state
echo "Cleaning up previous task artifacts..."
# Find ID of existing promotion
OLD_PROMO_ID=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data WHERE name LIKE '%Influencer Summer Campaign%' LIMIT 1")
if [ -n "$OLD_PROMO_ID" ]; then
    echo "Removing old promotion ID: $OLD_PROMO_ID"
    # Delete coupons linked to this promo
    drupal_db_query "DELETE FROM commerce_promotion_coupon WHERE promotion_id = $OLD_PROMO_ID"
    # Delete the promotion itself
    drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE promotion_id = $OLD_PROMO_ID"
    drupal_db_query "DELETE FROM commerce_promotion__coupons WHERE entity_id = $OLD_PROMO_ID"
    drupal_db_query "DELETE FROM commerce_promotion__conditions WHERE entity_id = $OLD_PROMO_ID"
fi

# Also clean up coupons by code if they exist orphaned
for code in "INFL-EMMA" "INFL-ALEX" "INFL-SARA" "INFL-MIKE" "INFL-LILY"; do
    drupal_db_query "DELETE FROM commerce_promotion_coupon WHERE code = '$code'"
done

# Record baseline counts
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
echo "${INITIAL_PROMO_COUNT:-0}" > /tmp/initial_promo_count

INITIAL_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
echo "${INITIAL_COUPON_COUNT:-0}" > /tmp/initial_coupon_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Promotions page to save time
echo "Navigating to Promotions page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="