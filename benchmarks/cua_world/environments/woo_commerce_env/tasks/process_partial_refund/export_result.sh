#!/bin/bash
echo "=== Exporting Process Partial Refund Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Load saved state
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null)
CHARGER_ID=$(cat /tmp/target_charger_product_id.txt 2>/dev/null)
INITIAL_REFUND_COUNT=$(cat /tmp/initial_refund_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Check if order still exists
ORDER_EXISTS=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE ID=$ORDER_ID AND post_type='shop_order' AND post_status != 'trash'")

# Get current refund count
CURRENT_REFUND_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='shop_order_refund' AND post_parent=$ORDER_ID")

# Get Details of the most recent refund for this order
REFUND_DATA=$(wc_query "SELECT ID, post_date_gmt, post_excerpt 
    FROM wp_posts 
    WHERE post_type='shop_order_refund' AND post_parent=$ORDER_ID 
    ORDER BY ID DESC LIMIT 1")

REFUND_ID=""
REFUND_DATE=""
REFUND_REASON=""
REFUND_AMOUNT="0"
REFUNDED_ITEMS_JSON="[]"

if [ -n "$REFUND_DATA" ]; then
    REFUND_ID=$(echo "$REFUND_DATA" | cut -f1)
    REFUND_DATE=$(echo "$REFUND_DATA" | cut -f2)
    REFUND_REASON=$(echo "$REFUND_DATA" | cut -f3)
    
    # Get refund amount
    REFUND_AMOUNT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$REFUND_ID AND meta_key='_refund_amount' LIMIT 1")
    
    # Get items included in this refund
    # refunds store line items similarly to orders in wp_woocommerce_order_items
    # The meta _qty will be negative, and _product_id links to the product
    # We want to see WHICH product was refunded
    
    REFUND_ITEMS_RAW=$(wc_query "SELECT oim.meta_value 
        FROM wp_woocommerce_order_items oi
        JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id
        WHERE oi.order_id = $REFUND_ID
        AND oi.order_item_type = 'line_item'
        AND oim.meta_key = '_product_id'")
    
    # Build JSON array of product IDs in this refund
    REFUNDED_ITEMS_JSON="["
    FIRST=true
    for pid in $REFUND_ITEMS_RAW; do
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            REFUNDED_ITEMS_JSON="$REFUNDED_ITEMS_JSON,"
        fi
        REFUNDED_ITEMS_JSON="$REFUNDED_ITEMS_JSON $pid"
    done
    REFUNDED_ITEMS_JSON="$REFUNDED_ITEMS_JSON]"
fi

# Escape reason for JSON
REFUND_REASON_ESC=$(json_escape "$REFUND_REASON")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "order_id": "${ORDER_ID:-0}",
    "order_exists": $([ "$ORDER_EXISTS" = "1" ] && echo "true" || echo "false"),
    "target_charger_id": "${CHARGER_ID:-0}",
    "initial_refund_count": ${INITIAL_REFUND_COUNT:-0},
    "current_refund_count": ${CURRENT_REFUND_COUNT:-0},
    "refund": {
        "id": "${REFUND_ID:-0}",
        "date_gmt": "$REFUND_DATE",
        "reason": "$REFUND_REASON_ESC",
        "amount": "${REFUND_AMOUNT:-0}",
        "product_ids": $REFUNDED_ITEMS_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="