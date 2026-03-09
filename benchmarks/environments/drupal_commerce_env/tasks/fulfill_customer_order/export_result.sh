#!/bin/bash
# Export script for fulfill_customer_order task
echo "=== Exporting fulfill_customer_order Result ==="

. /workspace/scripts/task_utils.sh

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
take_screenshot /tmp/task_end_screenshot.png

# Get baseline
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")
INITIAL_ORDER_ITEM_COUNT=$(cat /tmp/initial_order_item_count 2>/dev/null || echo "0")

# Query current order count
CURRENT_ORDER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order")
CURRENT_ORDER_COUNT=${CURRENT_ORDER_COUNT:-0}
NEW_ORDERS=$((CURRENT_ORDER_COUNT - INITIAL_ORDER_COUNT))

# Find orders for janesmith (uid=3) created after task start
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get the most recent order for janesmith
ORDER_DATA=$(drupal_db_query "SELECT order_id, uid, state, mail, total_price__number, total_price__currency_code, billing_profile__target_id FROM commerce_order WHERE uid=3 ORDER BY order_id DESC LIMIT 1")

ORDER_ID=""
ORDER_UID=""
ORDER_STATE=""
ORDER_MAIL=""
ORDER_TOTAL=""
ORDER_CURRENCY=""
BILLING_PROFILE_ID=""

if [ -n "$ORDER_DATA" ]; then
    ORDER_ID=$(echo "$ORDER_DATA" | cut -f1)
    ORDER_UID=$(echo "$ORDER_DATA" | cut -f2)
    ORDER_STATE=$(echo "$ORDER_DATA" | cut -f3)
    ORDER_MAIL=$(echo "$ORDER_DATA" | cut -f4)
    ORDER_TOTAL=$(echo "$ORDER_DATA" | cut -f5)
    ORDER_CURRENCY=$(echo "$ORDER_DATA" | cut -f6)
    BILLING_PROFILE_ID=$(echo "$ORDER_DATA" | cut -f7)
fi

# Check order items for this order
HAS_SONY="false"
HAS_LOGI="false"
ITEM_COUNT=0

if [ -n "$ORDER_ID" ]; then
    # Get order items via the junction table
    ORDER_ITEMS=$(drupal_db_query "SELECT oi.purchased_entity, oi.title, oi.quantity, oi.unit_price__number FROM commerce_order_item oi INNER JOIN commerce_order__order_items ooi ON oi.order_item_id = ooi.order_items_target_id WHERE ooi.entity_id = $ORDER_ID")

    ITEM_COUNT=$(echo "$ORDER_ITEMS" | grep -c "." 2>/dev/null || echo "0")

    # Check for specific SKUs via purchased_entity (variation_id)
    # Sony WH-1000XM5 = variation_id 1, Logitech MX Master = variation_id 5
    if echo "$ORDER_ITEMS" | grep -qE "^1\t"; then
        HAS_SONY="true"
    fi
    if echo "$ORDER_ITEMS" | grep -qE "^5\t"; then
        HAS_LOGI="true"
    fi
fi

# Check if coupon was applied to the order
HAS_COUPON="false"
if [ -n "$ORDER_ID" ]; then
    COUPON_APPLIED=$(drupal_db_query "SELECT coupons_target_id FROM commerce_order__coupons WHERE entity_id = $ORDER_ID")
    if [ -n "$COUPON_APPLIED" ]; then
        HAS_COUPON="true"
    fi
fi

# Check for discount adjustment
HAS_DISCOUNT="false"
DISCOUNT_AMOUNT="0"
if [ -n "$ORDER_ID" ]; then
    ADJUSTMENT_DATA=$(drupal_db_query "SELECT adjustments__type, adjustments__amount__number FROM commerce_order__adjustments WHERE entity_id = $ORDER_ID AND adjustments__type = 'promotion'")
    if [ -n "$ADJUSTMENT_DATA" ]; then
        HAS_DISCOUNT="true"
        DISCOUNT_AMOUNT=$(echo "$ADJUSTMENT_DATA" | head -1 | cut -f2)
    fi
fi

# Check billing address
BILLING_CITY=""
BILLING_STATE=""
BILLING_GIVEN_NAME=""
BILLING_FAMILY_NAME=""
HAS_BILLING="false"
if [ -n "$BILLING_PROFILE_ID" ] && [ "$BILLING_PROFILE_ID" != "NULL" ] && [ "$BILLING_PROFILE_ID" != "" ]; then
    BILLING_DATA=$(drupal_db_query "SELECT address_given_name, address_family_name, address_locality, address_administrative_area FROM profile__address WHERE entity_id = $BILLING_PROFILE_ID LIMIT 1")
    if [ -n "$BILLING_DATA" ]; then
        HAS_BILLING="true"
        BILLING_GIVEN_NAME=$(echo "$BILLING_DATA" | cut -f1)
        BILLING_FAMILY_NAME=$(echo "$BILLING_DATA" | cut -f2)
        BILLING_CITY=$(echo "$BILLING_DATA" | cut -f3)
        BILLING_STATE=$(echo "$BILLING_DATA" | cut -f4)
    fi
fi

# Determine if order is placed (not draft)
ORDER_PLACED="false"
if [ -n "$ORDER_STATE" ] && [ "$ORDER_STATE" != "draft" ] && [ "$ORDER_STATE" != "" ] && [ "$ORDER_STATE" != "NULL" ]; then
    ORDER_PLACED="true"
fi

cat > /tmp/fulfill_customer_order_result.json << EOF
{
    "order_found": $([ -n "$ORDER_ID" ] && echo "true" || echo "false"),
    "order_id": ${ORDER_ID:-null},
    "order_uid": ${ORDER_UID:-null},
    "order_state": "$(echo "$ORDER_STATE" | tr -d '\n\r')",
    "order_placed": $ORDER_PLACED,
    "order_mail": "$(echo "$ORDER_MAIL" | tr -d '\n\r')",
    "order_total": "${ORDER_TOTAL:-0}",
    "order_currency": "$(echo "$ORDER_CURRENCY" | tr -d '\n\r')",
    "new_orders": $NEW_ORDERS,
    "item_count": $ITEM_COUNT,
    "has_sony": $HAS_SONY,
    "has_logi": $HAS_LOGI,
    "has_coupon_applied": $HAS_COUPON,
    "has_discount": $HAS_DISCOUNT,
    "discount_amount": "${DISCOUNT_AMOUNT:-0}",
    "has_billing_address": $HAS_BILLING,
    "billing_city": "$(echo "$BILLING_CITY" | tr -d '\n\r')",
    "billing_state": "$(echo "$BILLING_STATE" | tr -d '\n\r')",
    "billing_given_name": "$(echo "$BILLING_GIVEN_NAME" | tr -d '\n\r')",
    "billing_family_name": "$(echo "$BILLING_FAMILY_NAME" | tr -d '\n\r')",
    "initial_order_count": $INITIAL_ORDER_COUNT,
    "current_order_count": $CURRENT_ORDER_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/fulfill_customer_order_result.json
echo "=== Export Complete ==="
