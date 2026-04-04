#!/bin/bash
# Export script for process_customer_refund task
echo "=== Exporting process_customer_refund Result ==="

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

# Clear cache
cd /var/www/html/drupal && vendor/bin/drush cr 2>/dev/null || true

# Get baseline
INITIAL_PROMO_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")
ORDER_ID=$(cat /tmp/refund_order_id 2>/dev/null || echo "0")
INITIAL_ORDER_STATE=$(cat /tmp/initial_order_state 2>/dev/null || echo "completed")

# Check current order state
ORDER_STATE=""
ORDER_UID=""
ORDER_TOTAL=""
if [ "$ORDER_ID" != "0" ] && [ -n "$ORDER_ID" ]; then
    ORDER_DATA=$(drupal_db_query "SELECT state, uid, total_price__number FROM commerce_order WHERE order_id=$ORDER_ID")
    ORDER_STATE=$(echo "$ORDER_DATA" | cut -f1)
    ORDER_UID=$(echo "$ORDER_DATA" | cut -f2)
    ORDER_TOTAL=$(echo "$ORDER_DATA" | cut -f3)
fi

ORDER_CANCELED="false"
if [ "$ORDER_STATE" = "canceled" ]; then
    ORDER_CANCELED="true"
fi

# Check for refund promotion
REFUND_PROMO=$(drupal_db_query "SELECT promotion_id, name, offer__target_plugin_id, status, require_coupon FROM commerce_promotion_field_data WHERE name LIKE '%Refund%' OR name LIKE '%refund%' OR name LIKE '%Store Credit%' OR name LIKE '%store credit%' ORDER BY promotion_id DESC LIMIT 1")

REFUND_PROMO_FOUND="false"
REFUND_PROMO_ID=""
REFUND_PROMO_NAME=""
REFUND_PROMO_OFFER_TYPE=""
REFUND_PROMO_STATUS=""
REFUND_PROMO_REQUIRE_COUPON=""

if [ -n "$REFUND_PROMO" ]; then
    REFUND_PROMO_FOUND="true"
    REFUND_PROMO_ID=$(echo "$REFUND_PROMO" | cut -f1)
    REFUND_PROMO_NAME=$(echo "$REFUND_PROMO" | cut -f2)
    REFUND_PROMO_OFFER_TYPE=$(echo "$REFUND_PROMO" | cut -f3)
    REFUND_PROMO_STATUS=$(echo "$REFUND_PROMO" | cut -f4)
    REFUND_PROMO_REQUIRE_COUPON=$(echo "$REFUND_PROMO" | cut -f5)
fi

# Check offer amount for the refund promotion
REFUND_AMOUNT=""
if [ -n "$REFUND_PROMO_ID" ]; then
    REFUND_AMOUNT=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id=$REFUND_PROMO_ID" | python3 -c "
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

# Check for REFUND-JOHNDOE coupon
COUPON_DATA=$(drupal_db_query "SELECT id, code, usage_limit, status FROM commerce_promotion_coupon WHERE code='REFUND-JOHNDOE' ORDER BY id DESC LIMIT 1")
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

# Check if coupon is linked to refund promotion
COUPON_LINKED="false"
if [ -n "$REFUND_PROMO_ID" ] && [ -n "$COUPON_ID" ]; then
    LINK_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__coupons WHERE entity_id=$REFUND_PROMO_ID AND coupons_target_id=$COUPON_ID")
    if [ "$LINK_CHECK" -gt 0 ] 2>/dev/null; then
        COUPON_LINKED="true"
    fi
fi

# Check store assignment for refund promotion
STORE_ASSIGNED="false"
if [ -n "$REFUND_PROMO_ID" ]; then
    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id=$REFUND_PROMO_ID AND stores_target_id=1")
    if [ "$STORE_CHECK" -gt 0 ] 2>/dev/null; then
        STORE_ASSIGNED="true"
    fi
fi

CURRENT_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
CURRENT_PROMO_COUNT=${CURRENT_PROMO_COUNT:-0}

cat > /tmp/process_customer_refund_result.json << EOF
{
    "order_id": ${ORDER_ID:-null},
    "order_uid": ${ORDER_UID:-null},
    "initial_order_state": "$(echo "$INITIAL_ORDER_STATE" | tr -d '\n\r')",
    "current_order_state": "$(echo "$ORDER_STATE" | tr -d '\n\r')",
    "order_canceled": $ORDER_CANCELED,
    "order_total": "${ORDER_TOTAL:-0}",
    "refund_promo_found": $REFUND_PROMO_FOUND,
    "refund_promo_id": ${REFUND_PROMO_ID:-null},
    "refund_promo_name": "$(echo "$REFUND_PROMO_NAME" | tr -d '\n\r')",
    "refund_promo_offer_type": "$(echo "$REFUND_PROMO_OFFER_TYPE" | tr -d '\n\r')",
    "refund_promo_status": ${REFUND_PROMO_STATUS:-0},
    "refund_promo_require_coupon": ${REFUND_PROMO_REQUIRE_COUPON:-0},
    "refund_amount": "${REFUND_AMOUNT:-}",
    "coupon_found": $COUPON_FOUND,
    "coupon_code": "$(echo "$COUPON_CODE" | tr -d '\n\r')",
    "coupon_usage_limit": ${COUPON_USAGE_LIMIT:-0},
    "coupon_linked": $COUPON_LINKED,
    "store_assigned": $STORE_ASSIGNED,
    "initial_promo_count": $INITIAL_PROMO_COUNT,
    "current_promo_count": $CURRENT_PROMO_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/process_customer_refund_result.json
echo "=== Export Complete ==="
