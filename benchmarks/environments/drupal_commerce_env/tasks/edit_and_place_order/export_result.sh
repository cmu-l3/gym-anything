#!/bin/bash
# Export script for edit_and_place_order task
echo "=== Exporting edit_and_place_order Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve the target order ID
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null || echo "")

if [ -z "$ORDER_ID" ]; then
    echo "ERROR: No target order ID found from setup."
    # Create empty result to avoid verifier crash
    echo '{"error": "Setup failed"}' > /tmp/task_result.json
    exit 0
fi

echo "Checking Order ID: $ORDER_ID"

# 1. Get Order Details (State, Billing Profile ID)
ORDER_DATA=$(drupal_db_query "SELECT state, billing_profile__target_id FROM commerce_order WHERE order_id = $ORDER_ID")
ORDER_STATE=$(echo "$ORDER_DATA" | awk '{print $1}')
BILLING_PROFILE_ID=$(echo "$ORDER_DATA" | awk '{print $2}')

echo "Final State: $ORDER_STATE"
echo "Billing Profile ID: $BILLING_PROFILE_ID"

# 2. Get Order Items (SKUs)
# Join commerce_order_item with variation data to get SKUs directly
# commerce_order__order_items links order to items
# commerce_order_item links item to purchased_entity (variation)
# commerce_product_variation_field_data links variation to SKU
ITEMS_QUERY="
SELECT v.sku 
FROM commerce_order__order_items oi_link
JOIN commerce_order_item oi ON oi_link.order_items_target_id = oi.order_item_id
JOIN commerce_product_variation_field_data v ON oi.purchased_entity = v.variation_id
WHERE oi_link.entity_id = $ORDER_ID
"
ORDER_ITEMS_SKUS=$(drupal_db_query "$ITEMS_QUERY")
# Convert newlines to comma-separated string for JSON
SKU_LIST=$(echo "$ORDER_ITEMS_SKUS" | tr '\n' ',' | sed 's/,$//')

echo "Items found: $SKU_LIST"

# 3. Get Billing Address Details
BILLING_LOCALITY=""
BILLING_AREA=""
BILLING_CODE=""
BILLING_ADDRESS_LINE=""

if [ -n "$BILLING_PROFILE_ID" ] && [ "$BILLING_PROFILE_ID" != "NULL" ]; then
    ADDRESS_DATA=$(drupal_db_query "SELECT address_locality, address_administrative_area, address_postal_code, address_address_line1 FROM profile__address WHERE entity_id = $BILLING_PROFILE_ID")
    # Use tab delimiter
    BILLING_LOCALITY=$(echo "$ADDRESS_DATA" | cut -f1)
    BILLING_AREA=$(echo "$ADDRESS_DATA" | cut -f2)
    BILLING_CODE=$(echo "$ADDRESS_DATA" | cut -f3)
    BILLING_ADDRESS_LINE=$(echo "$ADDRESS_DATA" | cut -f4)
fi

echo "Billing: $BILLING_LOCALITY, $BILLING_AREA $BILLING_CODE"

# 4. Check timestamps to ensure modification happened during task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORDER_CHANGED=$(drupal_db_query "SELECT changed FROM commerce_order WHERE order_id = $ORDER_ID")

MODIFIED_DURING_TASK="false"
if [ "$ORDER_CHANGED" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 5. Generate JSON Result
# We use a temp file and python to ensure safe JSON escaping
python3 -c "
import json
import sys

data = {
    'order_id': '$ORDER_ID',
    'order_state': '$ORDER_STATE',
    'skus': '$SKU_LIST'.split(',') if '$SKU_LIST' else [],
    'billing': {
        'locality': '$BILLING_LOCALITY',
        'administrative_area': '$BILLING_AREA',
        'postal_code': '$BILLING_CODE',
        'address_line1': '$BILLING_ADDRESS_LINE'
    },
    'modified_during_task': $MODIFIED_DURING_TASK
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="