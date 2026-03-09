#!/bin/bash
# Export script for configure_seasonal_promotion task
echo "=== Exporting configure_seasonal_promotion Result ==="

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

# Get baseline
INITIAL_PROMO_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")

# Find the new promotion by name
PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name, display_name, offer__target_plugin_id, status, require_coupon, usage_limit FROM commerce_promotion_field_data WHERE name LIKE '%Spring Clearance%' ORDER BY promotion_id DESC LIMIT 1")

PROMO_ID=""
PROMO_NAME=""
PROMO_DISPLAY_NAME=""
PROMO_OFFER_TYPE=""
PROMO_STATUS=""
PROMO_REQUIRE_COUPON=""
PROMO_USAGE_LIMIT=""
PROMO_FOUND="false"

if [ -n "$PROMO_DATA" ]; then
    PROMO_FOUND="true"
    PROMO_ID=$(echo "$PROMO_DATA" | cut -f1)
    PROMO_NAME=$(echo "$PROMO_DATA" | cut -f2)
    PROMO_DISPLAY_NAME=$(echo "$PROMO_DATA" | cut -f3)
    PROMO_OFFER_TYPE=$(echo "$PROMO_DATA" | cut -f4)
    PROMO_STATUS=$(echo "$PROMO_DATA" | cut -f5)
    PROMO_REQUIRE_COUPON=$(echo "$PROMO_DATA" | cut -f6)
    PROMO_USAGE_LIMIT=$(echo "$PROMO_DATA" | cut -f7)
fi

# Check offer configuration (percentage value) using Python for blob parsing
OFFER_PERCENTAGE=""
if [ -n "$PROMO_ID" ]; then
    OFFER_PERCENTAGE=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id=$PROMO_ID" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'\"percentage\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    m2 = re.search(r'percentage.*?([0-9.]+)', data)
    if m2:
        print(m2.group(1))
    else:
        print('')
" 2>/dev/null)
fi

# Check for SPRING30 coupon
COUPON_DATA=$(drupal_db_query "SELECT id, code, usage_limit, status FROM commerce_promotion_coupon WHERE code='SPRING30' ORDER BY id DESC LIMIT 1")
COUPON_FOUND="false"
COUPON_CODE=""
COUPON_USAGE_LIMIT=""
COUPON_STATUS=""
COUPON_ID=""

if [ -n "$COUPON_DATA" ]; then
    COUPON_FOUND="true"
    COUPON_ID=$(echo "$COUPON_DATA" | cut -f1)
    COUPON_CODE=$(echo "$COUPON_DATA" | cut -f2)
    COUPON_USAGE_LIMIT=$(echo "$COUPON_DATA" | cut -f3)
    COUPON_STATUS=$(echo "$COUPON_DATA" | cut -f4)
fi

# Check if coupon is linked to the promotion
COUPON_LINKED="false"
if [ -n "$PROMO_ID" ] && [ -n "$COUPON_ID" ]; then
    LINK_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__coupons WHERE entity_id=$PROMO_ID AND coupons_target_id=$COUPON_ID")
    if [ "$LINK_CHECK" -gt 0 ] 2>/dev/null; then
        COUPON_LINKED="true"
    fi
fi

# Check for minimum order condition
HAS_MIN_ORDER_CONDITION="false"
MIN_ORDER_AMOUNT=""
if [ -n "$PROMO_ID" ]; then
    CONDITION_DATA=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id=$PROMO_ID AND conditions__target_plugin_id='order_total_price'")
    if [ -n "$CONDITION_DATA" ]; then
        HAS_MIN_ORDER_CONDITION="true"
        MIN_ORDER_AMOUNT=$(echo "$CONDITION_DATA" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    m2 = re.search(r'number.*?([0-9.]+)', data)
    if m2:
        print(m2.group(1))
    else:
        print('')
" 2>/dev/null)
    fi
fi

# Check store assignment
STORE_ASSIGNED="false"
if [ -n "$PROMO_ID" ]; then
    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id=$PROMO_ID AND stores_target_id=1")
    if [ "$STORE_CHECK" -gt 0 ] 2>/dev/null; then
        STORE_ASSIGNED="true"
    fi
fi

# Current counts
CURRENT_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
CURRENT_PROMO_COUNT=${CURRENT_PROMO_COUNT:-0}
CURRENT_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
CURRENT_COUPON_COUNT=${CURRENT_COUPON_COUNT:-0}

cat > /tmp/configure_seasonal_promotion_result.json << EOF
{
    "promotion_found": $PROMO_FOUND,
    "promotion_id": ${PROMO_ID:-null},
    "promotion_name": "$(echo "$PROMO_NAME" | tr -d '\n\r')",
    "promotion_display_name": "$(echo "$PROMO_DISPLAY_NAME" | tr -d '\n\r')",
    "promotion_offer_type": "$(echo "$PROMO_OFFER_TYPE" | tr -d '\n\r')",
    "promotion_status": ${PROMO_STATUS:-0},
    "promotion_require_coupon": ${PROMO_REQUIRE_COUPON:-0},
    "offer_percentage": "${OFFER_PERCENTAGE:-}",
    "coupon_found": $COUPON_FOUND,
    "coupon_code": "$(echo "$COUPON_CODE" | tr -d '\n\r')",
    "coupon_usage_limit": ${COUPON_USAGE_LIMIT:-0},
    "coupon_status": ${COUPON_STATUS:-0},
    "coupon_linked_to_promotion": $COUPON_LINKED,
    "has_min_order_condition": $HAS_MIN_ORDER_CONDITION,
    "min_order_amount": "${MIN_ORDER_AMOUNT:-}",
    "store_assigned": $STORE_ASSIGNED,
    "initial_promo_count": $INITIAL_PROMO_COUNT,
    "current_promo_count": $CURRENT_PROMO_COUNT,
    "initial_coupon_count": $INITIAL_COUPON_COUNT,
    "current_coupon_count": $CURRENT_COUPON_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/configure_seasonal_promotion_result.json
echo "=== Export Complete ==="
