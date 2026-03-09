#!/bin/bash
# Export script for Setup Volume Discount task
echo "=== Exporting Setup Volume Discount Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definition
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get baseline
INITIAL_PROMO_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
CURRENT_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
CURRENT_PROMO_COUNT=${CURRENT_PROMO_COUNT:-0}

# Find the new promotion by name
# We look for the most recently created one matching the name pattern
PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name, offer__target_plugin_id, status, require_coupon, offer__target_plugin_configuration FROM commerce_promotion_field_data WHERE name LIKE '%Volume Discount%' ORDER BY promotion_id DESC LIMIT 1")

PROMO_FOUND="false"
PROMO_ID=""
PROMO_NAME=""
OFFER_PLUGIN=""
PROMO_STATUS=""
REQUIRE_COUPON=""
OFFER_CONFIG=""

if [ -n "$PROMO_DATA" ]; then
    PROMO_FOUND="true"
    # Extract fields (tab separated by default in mysql -N)
    # Note: The configuration blob is the last field and might contain tabs/newlines,
    # so we handle it carefully.
    PROMO_ID=$(echo "$PROMO_DATA" | cut -f1)
    PROMO_NAME=$(echo "$PROMO_DATA" | cut -f2)
    OFFER_PLUGIN=$(echo "$PROMO_DATA" | cut -f3)
    PROMO_STATUS=$(echo "$PROMO_DATA" | cut -f4)
    REQUIRE_COUPON=$(echo "$PROMO_DATA" | cut -f5)
    
    # Re-fetch configuration separately to avoid parsing issues with cut
    OFFER_CONFIG=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id=$PROMO_ID")
fi

# Check Condition Configuration
CONDITION_PLUGIN=""
CONDITION_CONFIG=""
HAS_CONDITION="false"

if [ -n "$PROMO_ID" ]; then
    # Look for the quantity condition
    COND_DATA=$(drupal_db_query "SELECT conditions__target_plugin_id, CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id=$PROMO_ID AND conditions__target_plugin_id='order_item_quantity' LIMIT 1")
    
    if [ -n "$COND_DATA" ]; then
        HAS_CONDITION="true"
        CONDITION_PLUGIN=$(echo "$COND_DATA" | cut -f1)
        # Re-fetch config to be safe
        CONDITION_CONFIG=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id=$PROMO_ID AND conditions__target_plugin_id='order_item_quantity' LIMIT 1")
    fi
fi

# Check Store Assignment
STORE_ASSIGNED="false"
if [ -n "$PROMO_ID" ]; then
    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id=$PROMO_ID AND stores_target_id=1")
    if [ "$STORE_CHECK" -gt 0 ] 2>/dev/null; then
        STORE_ASSIGNED="true"
    fi
fi

# Use Python to parse the serialized PHP configuration blobs
# This is robust against PHP serialization format
PYTHON_PARSER_SCRIPT=$(cat <<EOF
import sys
import re
import json

def parse_php_value(data, key):
    # Regex to find "key";s:Len:"value" or "key";i:value or "key";d:value
    # 1. String: "percentage";s:4:"0.10"
    m_str = re.search(f'"{key}";s:\d+:"([^"]+)"', data)
    if m_str: return m_str.group(1)
    
    # 2. Integer/Decimal directly: "quantity";i:5 or "quantity";d:5
    m_num = re.search(f'"{key}";[id]:([0-9.]+)', data)
    if m_num: return m_num.group(1)
    
    return None

offer_config = """$OFFER_CONFIG"""
cond_config = """$CONDITION_CONFIG"""

result = {
    "percentage": parse_php_value(offer_config, "percentage"),
    "quantity": parse_php_value(cond_config, "quantity"),
    "operator": parse_php_value(cond_config, "operator")
}
print(json.dumps(result))
EOF
)

PARSED_VALUES=$(python3 -c "$PYTHON_PARSER_SCRIPT" 2>/dev/null || echo '{"percentage": null, "quantity": null, "operator": null}')

# Create the final JSON result
cat > /tmp/task_result.json << EOF
{
    "initial_promo_count": $INITIAL_PROMO_COUNT,
    "current_promo_count": $CURRENT_PROMO_COUNT,
    "promotion_found": $PROMO_FOUND,
    "promotion_id": ${PROMO_ID:-null},
    "promotion_name": "$(json_escape "$PROMO_NAME")",
    "offer_plugin": "$(json_escape "$OFFER_PLUGIN")",
    "promotion_status": ${PROMO_STATUS:-0},
    "require_coupon": ${REQUIRE_COUPON:-1},
    "has_quantity_condition": $HAS_CONDITION,
    "condition_plugin": "$(json_escape "$CONDITION_PLUGIN")",
    "store_assigned": $STORE_ASSIGNED,
    "parsed_values": $PARSED_VALUES,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json