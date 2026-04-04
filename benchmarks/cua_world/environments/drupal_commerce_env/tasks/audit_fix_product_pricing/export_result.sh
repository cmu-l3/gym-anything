#!/bin/bash
# Export script for audit_fix_product_pricing task
echo "=== Exporting audit_fix_product_pricing Result ==="

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

take_screenshot /tmp/task_end_screenshot.png

# Clear Drupal cache to ensure DB reflects latest state
cd /var/www/html/drupal && vendor/bin/drush cr 2>/dev/null || true

# Get baseline values
INITIAL_BOSE_PRICE=$(cat /tmp/initial_bose_price 2>/dev/null || echo "299.000000")
INITIAL_WD_PRICE=$(cat /tmp/initial_wd_price 2>/dev/null || echo "149.990000")
INITIAL_CORSAIR_SKU=$(cat /tmp/initial_corsair_sku 2>/dev/null || echo "CORSAIR-DDR5-32G")
INITIAL_SONY_LIST=$(cat /tmp/initial_sony_list_price 2>/dev/null || echo "NULL")
INITIAL_ANKER_STATUS=$(cat /tmp/initial_anker_status 2>/dev/null || echo "1")

# Query current state for each product
# 1. Bose price
BOSE_CURRENT_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE variation_id=4")
BOSE_CURRENT_PRICE=${BOSE_CURRENT_PRICE:-0}
echo "Bose current price: $BOSE_CURRENT_PRICE"

# 2. WD price
WD_CURRENT_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE variation_id=9")
WD_CURRENT_PRICE=${WD_CURRENT_PRICE:-0}
echo "WD current price: $WD_CURRENT_PRICE"

# 3. Corsair SKU
CORSAIR_CURRENT_SKU=$(drupal_db_query "SELECT sku FROM commerce_product_variation_field_data WHERE variation_id=12")
CORSAIR_CURRENT_SKU=${CORSAIR_CURRENT_SKU:-unknown}
echo "Corsair current SKU: $CORSAIR_CURRENT_SKU"

# 4. Sony list price
SONY_CURRENT_LIST=$(drupal_db_query "SELECT list_price__number FROM commerce_product_variation_field_data WHERE variation_id=1")
SONY_CURRENT_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE variation_id=1")
echo "Sony current list price: ${SONY_CURRENT_LIST:-(NULL)}"
echo "Sony current price: $SONY_CURRENT_PRICE"

# 5. Anker status
ANKER_CURRENT_STATUS=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE product_id=7")
ANKER_CURRENT_STATUS=${ANKER_CURRENT_STATUS:-1}
echo "Anker current status: $ANKER_CURRENT_STATUS"

# Compute changes
python3 << PYEOF
import json

result = {
    "bose_initial_price": "$INITIAL_BOSE_PRICE".strip(),
    "bose_current_price": "$BOSE_CURRENT_PRICE".strip(),
    "bose_price_changed": "$INITIAL_BOSE_PRICE".strip() != "$BOSE_CURRENT_PRICE".strip(),
    "wd_initial_price": "$INITIAL_WD_PRICE".strip(),
    "wd_current_price": "$WD_CURRENT_PRICE".strip(),
    "wd_price_changed": "$INITIAL_WD_PRICE".strip() != "$WD_CURRENT_PRICE".strip(),
    "corsair_initial_sku": "$INITIAL_CORSAIR_SKU".strip(),
    "corsair_current_sku": "$CORSAIR_CURRENT_SKU".strip(),
    "corsair_sku_changed": "$INITIAL_CORSAIR_SKU".strip() != "$CORSAIR_CURRENT_SKU".strip(),
    "sony_initial_list_price": "$INITIAL_SONY_LIST".strip(),
    "sony_current_list_price": "${SONY_CURRENT_LIST:-NULL}".strip(),
    "sony_current_price": "$SONY_CURRENT_PRICE".strip(),
    "sony_list_price_set": "${SONY_CURRENT_LIST:-NULL}".strip() not in ("NULL", "", "None"),
    "anker_initial_status": "$INITIAL_ANKER_STATUS".strip(),
    "anker_current_status": "$ANKER_CURRENT_STATUS".strip(),
    "anker_unpublished": "$ANKER_CURRENT_STATUS".strip() == "0",
    "export_timestamp": "$(date -Iseconds)"
}

with open("/tmp/audit_fix_product_pricing_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
