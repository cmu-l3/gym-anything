#!/bin/bash
# Export script for create_loyalty_promotion task
echo "=== Exporting create_loyalty_promotion Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# 1. Evidence
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Data
INITIAL_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
CURRENT_COUNT=${CURRENT_COUNT:-0}

# Find the specific promotion
# We look for the most recently created promotion that matches the name pattern
PROMO_ID=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data WHERE name LIKE '%Loyal Customer Reward%' OR display_name LIKE '%$20 Off%' ORDER BY promotion_id DESC LIMIT 1")

PROMO_FOUND="false"
PROMO_NAME=""
PROMO_DISPLAY_NAME=""
PROMO_STATUS=""
PROMO_OFFER_PLUGIN=""
PROMO_OFFER_CONFIG=""
PROMO_REQUIRE_COUPON=""
PROMO_USAGE_LIMIT=""
PROMO_CUSTOMER_LIMIT=""
STORE_LINKED="false"
CONDITION_CONFIG=""

if [ -n "$PROMO_ID" ]; then
    PROMO_FOUND="true"
    
    # Fetch basic fields
    DATA=$(drupal_db_query "SELECT name, display_name, status, offer__target_plugin_id, require_coupon, usage_limit, customer_usage_limit FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID")
    
    # Parse tab-separated output
    PROMO_NAME=$(echo "$DATA" | cut -f1)
    PROMO_DISPLAY_NAME=$(echo "$DATA" | cut -f2)
    PROMO_STATUS=$(echo "$DATA" | cut -f3)
    PROMO_OFFER_PLUGIN=$(echo "$DATA" | cut -f4)
    PROMO_REQUIRE_COUPON=$(echo "$DATA" | cut -f5)
    PROMO_USAGE_LIMIT=$(echo "$DATA" | cut -f6)
    PROMO_CUSTOMER_LIMIT=$(echo "$DATA" | cut -f7)
    
    # Fetch serialized configurations (Raw strings, will parse in Python/verification)
    PROMO_OFFER_CONFIG=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID")
    
    # Fetch conditions
    # We look for the order_total_price condition specifically
    CONDITION_CONFIG=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id = $PROMO_ID AND conditions__target_plugin_id = 'order_total_price' LIMIT 1")
    
    # Check store linkage
    STORE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id = $PROMO_ID AND stores_target_id = 1")
    if [ "$STORE_COUNT" -gt 0 ]; then
        STORE_LINKED="true"
    fi
fi

# 3. Create JSON Result
# We use Python to construct the JSON to safely handle the serialized blobs and escaping
python3 -c "
import json
import re

result = {
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'promotion_found': '$PROMO_FOUND' == 'true',
    'promotion_id': '$PROMO_ID',
    'name': '''$PROMO_NAME''',
    'display_name': '''$PROMO_DISPLAY_NAME''',
    'status': '$PROMO_STATUS',
    'offer_plugin': '$PROMO_OFFER_PLUGIN',
    'raw_offer_config': '''$PROMO_OFFER_CONFIG''',
    'raw_condition_config': '''$CONDITION_CONFIG''',
    'require_coupon': '$PROMO_REQUIRE_COUPON',
    'usage_limit': '$PROMO_USAGE_LIMIT',
    'customer_usage_limit': '$PROMO_CUSTOMER_LIMIT',
    'store_linked': '$STORE_LINKED' == 'true'
}

# Try to extract amount from offer config using regex
# Serialized PHP look like: ... \"number\";s:5:\"20.00\" ...
offer_match = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', result['raw_offer_config'])
if offer_match:
    result['extracted_offer_amount'] = offer_match.group(1)
else:
    # Try alternate format
    offer_match = re.search(r'number.*?([0-9.]+)', result['raw_offer_config'])
    result['extracted_offer_amount'] = offer_match.group(1) if offer_match else None

# Try to extract condition amount
cond_match = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', result['raw_condition_config'])
if cond_match:
    result['extracted_condition_amount'] = cond_match.group(1)
else:
    cond_match = re.search(r'number.*?([0-9.]+)', result['raw_condition_config'])
    result['extracted_condition_amount'] = cond_match.group(1) if cond_match else None

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# 4. Save to final location
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json