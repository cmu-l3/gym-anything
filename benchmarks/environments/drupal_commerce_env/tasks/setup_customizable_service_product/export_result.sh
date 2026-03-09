#!/bin/bash
# Export script for setup_customizable_service_product
echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We will use Drush to export configuration as JSON for verification
# This allows us to inspect complex nested arrays (like form displays) reliable
cd /var/www/html/drupal

echo "Exporting configuration state..."

# 1. Check Order Item Type
ORDER_ITEM_TYPE_JSON=$($DRUSH config:get commerce_order_item_type.service --format=json 2>/dev/null || echo "{}")

# 2. Check Field Storage (confirms field exists on entity type)
FIELD_STORAGE_JSON=$($DRUSH config:get field.storage.commerce_order_item.field_device_serial_number --format=json 2>/dev/null || echo "{}")

# 3. Check Field Config (confirms field is attached to 'service' bundle)
FIELD_CONFIG_JSON=$($DRUSH config:get field.field.commerce_order_item.service.field_device_serial_number --format=json 2>/dev/null || echo "{}")

# 4. Check Form Display (CRITICAL: is it enabled in Add to Cart?)
# The config ID for the 'add_to_cart' form mode on 'service' order item type
FORM_DISPLAY_JSON=$($DRUSH config:get core.entity_form_display.commerce_order_item.service.add_to_cart --format=json 2>/dev/null || echo "{}")

# 5. Check Product Type
PRODUCT_TYPE_JSON=$($DRUSH config:get commerce_product_type.service --format=json 2>/dev/null || echo "{}")

# 6. Check Product Entity (SQL query)
EXPECTED_SKU="SVC-IPHONE-SCREEN"
PRODUCT_DATA=$(drupal_db_query "
SELECT 
    p.product_id, 
    p.type, 
    p.title,
    v.sku,
    v.price__number
FROM commerce_product_field_data p
LEFT JOIN commerce_product__variations pv ON p.product_id = pv.entity_id
LEFT JOIN commerce_product_variation_field_data v ON pv.variations_target_id = v.variation_id
WHERE v.sku = '$EXPECTED_SKU'
LIMIT 1
" 2>/dev/null)

PRODUCT_FOUND="false"
PRODUCT_TYPE=""
PRODUCT_PRICE=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    # Parse tab-separated output
    PRODUCT_TYPE=$(echo "$PRODUCT_DATA" | awk '{print $2}')
    PRODUCT_PRICE=$(echo "$PRODUCT_DATA" | awk '{print $5}')
fi

# 7. Negative Check: Ensure Default order item type wasn't modified
DEFAULT_FORM_DISPLAY_JSON=$($DRUSH config:get core.entity_form_display.commerce_order_item.default.add_to_cart --format=json 2>/dev/null || echo "{}")

# Construct the result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_item_type_config": $ORDER_ITEM_TYPE_JSON,
    "field_storage_config": $FIELD_STORAGE_JSON,
    "field_config": $FIELD_CONFIG_JSON,
    "form_display_config": $FORM_DISPLAY_JSON,
    "product_type_config": $PRODUCT_TYPE_JSON,
    "default_form_display_config": $DEFAULT_FORM_DISPLAY_JSON,
    "product_found": $PRODUCT_FOUND,
    "product_type_actual": "$PRODUCT_TYPE",
    "product_price": "$PRODUCT_PRICE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete."