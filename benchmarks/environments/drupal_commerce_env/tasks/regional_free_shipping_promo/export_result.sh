#!/bin/bash
# Export script for Regional Free Shipping Promotion task
echo "=== Exporting Regional Free Shipping Result ==="

source /workspace/scripts/task_utils.sh

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

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Find the promotion by name
echo "Searching for promotion 'California Pilot'..."
PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name, offer__target_plugin_id, status, changed FROM commerce_promotion_field_data WHERE name = 'California Pilot' ORDER BY promotion_id DESC LIMIT 1")

PROMO_FOUND="false"
PROMO_ID=""
PROMO_NAME=""
OFFER_PLUGIN_ID=""
PROMO_STATUS="0"
PROMO_CHANGED="0"
IS_NEWLY_CREATED="false"

if [ -n "$PROMO_DATA" ]; then
    PROMO_FOUND="true"
    PROMO_ID=$(echo "$PROMO_DATA" | cut -f1)
    PROMO_NAME=$(echo "$PROMO_DATA" | cut -f2)
    OFFER_PLUGIN_ID=$(echo "$PROMO_DATA" | cut -f3)
    PROMO_STATUS=$(echo "$PROMO_DATA" | cut -f4)
    PROMO_CHANGED=$(echo "$PROMO_DATA" | cut -f5)
    
    # Check if modified/created after task start
    if [ "$PROMO_CHANGED" -gt "$TASK_START" ]; then
        IS_NEWLY_CREATED="true"
    fi
fi

# 2. Extract Offer Configuration (Percentage)
# The configuration is a serialized PHP array. We need to extract the percentage value.
OFFER_PERCENTAGE=""
if [ -n "$PROMO_ID" ]; then
    # Get raw serialized string
    OFFER_CONFIG_RAW=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID")
    
    # Use python to safely extract the value
    OFFER_PERCENTAGE=$(echo "$OFFER_CONFIG_RAW" | python3 -c "
import sys, re, phpserialize
try:
    data = sys.stdin.read().strip()
    # Simple regex fallback if phpserialize not available
    m = re.search(r'\"percentage\";s:[0-9]+:\"([0-9.]+)\"', data)
    if m:
        print(m.group(1))
    else:
        # Try finding just the number if structure varies
        m2 = re.search(r'percentage.*?([0-9.]+)', data)
        print(m2.group(1) if m2 else '')
except:
    print('')
")
fi

# 3. Check Conditions (Order Total and Address)
HAS_PRICE_CONDITION="false"
PRICE_CONDITION_AMOUNT=""
HAS_ADDRESS_CONDITION="false"
ADDRESS_CONDITION_COUNTRY=""
ADDRESS_CONDITION_ZONE=""

if [ -n "$PROMO_ID" ]; then
    # Get all conditions for this promotion
    # Conditions are stored in a related table with plugin IDs and configs
    
    # Check Price Condition (order_total_price)
    PRICE_CONFIG_RAW=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id = $PROMO_ID AND conditions__target_plugin_id LIKE '%order_total_price%' LIMIT 1")
    
    if [ -n "$PRICE_CONFIG_RAW" ]; then
        HAS_PRICE_CONDITION="true"
        PRICE_CONDITION_AMOUNT=$(echo "$PRICE_CONFIG_RAW" | python3 -c "
import sys, re
data = sys.stdin.read().strip()
m = re.search(r'\"number\";s:[0-9]+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    # Fallback loose match
    m2 = re.search(r'number.*?([0-9.]+)', data)
    print(m2.group(1) if m2 else '')
")
    fi
    
    # Check Address/Zone Condition
    # Plugin ID could be 'order_shipping_address' or similar
    ADDRESS_CONFIG_RAW=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id = $PROMO_ID AND (conditions__target_plugin_id LIKE '%address%' OR conditions__target_plugin_id LIKE '%zone%') LIMIT 1")
    
    if [ -n "$ADDRESS_CONFIG_RAW" ]; then
        HAS_ADDRESS_CONDITION="true"
        # Check for US and CA in the blob
        if echo "$ADDRESS_CONFIG_RAW" | grep -q "US"; then
            ADDRESS_CONDITION_COUNTRY="US"
        fi
        if echo "$ADDRESS_CONFIG_RAW" | grep -q "CA"; then
            ADDRESS_CONDITION_ZONE="CA"
        fi
    fi
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "promotion_found": $PROMO_FOUND,
    "promotion_id": "${PROMO_ID}",
    "promotion_name": "$(json_escape "$PROMO_NAME")",
    "promotion_status": "${PROMO_STATUS}",
    "is_newly_created": $IS_NEWLY_CREATED,
    "offer_plugin_id": "$(json_escape "$OFFER_PLUGIN_ID")",
    "offer_percentage": "${OFFER_PERCENTAGE}",
    "has_price_condition": $HAS_PRICE_CONDITION,
    "price_condition_amount": "${PRICE_CONDITION_AMOUNT}",
    "has_address_condition": $HAS_ADDRESS_CONDITION,
    "address_country": "${ADDRESS_CONDITION_COUNTRY}",
    "address_zone": "${ADDRESS_CONDITION_ZONE}"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json