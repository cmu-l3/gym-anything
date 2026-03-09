#!/bin/bash
# Setup script for audit_fix_product_pricing task
echo "=== Setting up audit_fix_product_pricing ==="

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

# Record baseline state for all 5 products being audited
echo "Recording baseline product state..."

# Bose (variation_id=4): should be $299.00 initially
BOSE_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE variation_id=4")
echo "$BOSE_PRICE" > /tmp/initial_bose_price
echo "Bose initial price: $BOSE_PRICE"

# WD (variation_id=9): should be $149.99 initially
WD_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE variation_id=9")
echo "$WD_PRICE" > /tmp/initial_wd_price
echo "WD initial price: $WD_PRICE"

# Corsair (variation_id=12): should be CORSAIR-DDR5-32G initially
CORSAIR_SKU=$(drupal_db_query "SELECT sku FROM commerce_product_variation_field_data WHERE variation_id=12")
echo "$CORSAIR_SKU" > /tmp/initial_corsair_sku
echo "Corsair initial SKU: $CORSAIR_SKU"

# Sony (variation_id=1): list_price should be NULL initially
SONY_LIST=$(drupal_db_query "SELECT list_price__number FROM commerce_product_variation_field_data WHERE variation_id=1")
echo "$SONY_LIST" > /tmp/initial_sony_list_price
echo "Sony initial list price: ${SONY_LIST:-(NULL)}"

# Anker (product_id=7): should be status=1 initially
ANKER_STATUS=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE product_id=7")
echo "$ANKER_STATUS" > /tmp/initial_anker_status
echo "Anker initial status: $ANKER_STATUS"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to products list
navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
