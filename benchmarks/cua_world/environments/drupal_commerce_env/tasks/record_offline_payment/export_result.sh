#!/bin/bash
# Export script for record_offline_payment task
echo "=== Exporting record_offline_payment Result ==="

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
    create_result_json() {
        # Basic implementation if not available
        local out=$1
        shift
        echo "{" > "$out"
        echo "\"exported\": true" >> "$out"
        echo "}"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get target order ID
TARGET_ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null)
if [ -z "$TARGET_ORDER_ID" ]; then
    # Fallback: find most recent order for mikewilson
    MIKE_UID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='mikewilson'")
    if [ -n "$MIKE_UID" ]; then
        TARGET_ORDER_ID=$(drupal_db_query "SELECT order_id FROM commerce_order WHERE uid=$MIKE_UID ORDER BY order_id DESC LIMIT 1")
    fi
fi

echo "Checking payments for Order ID: $TARGET_ORDER_ID"

PAYMENT_FOUND="false"
PAYMENT_ID=""
PAYMENT_AMOUNT=""
PAYMENT_STATE=""
PAYMENT_GATEWAY=""
ORDER_TOTAL_PAID=""
ORDER_TOTAL_PRICE=""

if [ -n "$TARGET_ORDER_ID" ]; then
    # Check for payment entity linked to this order
    # We look for the newest payment
    PAYMENT_DATA=$(drupal_db_query "SELECT payment_id, amount__number, state, payment_gateway FROM commerce_payment WHERE order_id = $TARGET_ORDER_ID ORDER BY payment_id DESC LIMIT 1")
    
    if [ -n "$PAYMENT_DATA" ]; then
        PAYMENT_FOUND="true"
        PAYMENT_ID=$(echo "$PAYMENT_DATA" | cut -f1)
        PAYMENT_AMOUNT=$(echo "$PAYMENT_DATA" | cut -f2)
        PAYMENT_STATE=$(echo "$PAYMENT_DATA" | cut -f3)
        PAYMENT_GATEWAY=$(echo "$PAYMENT_DATA" | cut -f4)
    fi

    # Check Order Total Paid vs Total Price
    ORDER_DATA=$(drupal_db_query "SELECT total_paid__number, total_price__number FROM commerce_order WHERE order_id = $TARGET_ORDER_ID")
    if [ -n "$ORDER_DATA" ]; then
        ORDER_TOTAL_PAID=$(echo "$ORDER_DATA" | cut -f1)
        ORDER_TOTAL_PRICE=$(echo "$ORDER_DATA" | cut -f2)
    fi
fi

# Check initial count to ensure we actually added one
INITIAL_COUNT=$(cat /tmp/initial_payment_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_payment WHERE order_id = $TARGET_ORDER_ID" 2>/dev/null || echo "0")
NEW_PAYMENTS=$((CURRENT_COUNT - INITIAL_COUNT))

# Create detailed result JSON
cat > /tmp/record_offline_payment_result.json << EOF
{
    "target_order_id": ${TARGET_ORDER_ID:-null},
    "payment_found": $PAYMENT_FOUND,
    "payment_id": ${PAYMENT_ID:-null},
    "payment_amount": "${PAYMENT_AMOUNT:-0}",
    "payment_state": "${PAYMENT_STATE:-unknown}",
    "payment_gateway": "${PAYMENT_GATEWAY:-unknown}",
    "order_total_paid": "${ORDER_TOTAL_PAID:-0}",
    "order_total_price": "${ORDER_TOTAL_PRICE:-0}",
    "new_payments_count": $NEW_PAYMENTS,
    "initial_payments_count": $INITIAL_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/record_offline_payment_result.json 2>/dev/null || true

echo "Result exported:"
cat /tmp/record_offline_payment_result.json
echo "=== Export Complete ==="