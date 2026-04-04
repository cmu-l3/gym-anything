#!/bin/bash
# Export script for Modify Order Items task

echo "=== Exporting Modify Order Items Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve setup data
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null)
INITIAL_TOTAL=$(cat /tmp/initial_order_total.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$ORDER_ID" ]; then
    echo '{"error": "setup_failed"}' > /tmp/task_result.json
    exit 1
fi

echo "Analyzing Order ID: $ORDER_ID"

# 1. Check if Order Exists and get modification time
ORDER_DATA=$(wc_query "SELECT post_status, post_modified FROM wp_posts WHERE ID=$ORDER_ID" 2>/dev/null)
ORDER_STATUS=$(echo "$ORDER_DATA" | cut -f1)
ORDER_MODIFIED_STR=$(echo "$ORDER_DATA" | cut -f2)
ORDER_MODIFIED_TS=$(date -d "$ORDER_MODIFIED_STR" +%s 2>/dev/null || echo "0")

# Check if modified during task
WAS_MODIFIED="false"
if [ "$ORDER_MODIFIED_TS" -gt "$TASK_START" ]; then
    WAS_MODIFIED="true"
fi

# 2. Check Order Items
# Get list of item names currently in the order
ORDER_ITEMS=$(wc_query "SELECT order_item_name FROM wp_woocommerce_order_items WHERE order_id=$ORDER_ID AND order_item_type='line_item'" 2>/dev/null)

# Check for removal of T-Shirt
HAS_TSHIRT="false"
if echo "$ORDER_ITEMS" | grep -qi "Organic Cotton T-Shirt"; then
    HAS_TSHIRT="true"
fi

# Check for addition of Sweater
HAS_SWEATER="false"
if echo "$ORDER_ITEMS" | grep -qi "Merino Wool Sweater"; then
    HAS_SWEATER="true"
fi

# 3. Check Sweater Quantity
SWEATER_QTY="0"
if [ "$HAS_SWEATER" = "true" ]; then
    # Get order_item_id for the sweater
    ITEM_ID=$(wc_query "SELECT order_item_id FROM wp_woocommerce_order_items WHERE order_id=$ORDER_ID AND order_item_type='line_item' AND order_item_name LIKE '%Merino Wool Sweater%' LIMIT 1" 2>/dev/null)
    if [ -n "$ITEM_ID" ]; then
        SWEATER_QTY=$(wc_query "SELECT meta_value FROM wp_woocommerce_order_itemmeta WHERE order_item_id=$ITEM_ID AND meta_key='_qty'" 2>/dev/null)
    fi
fi

# 4. Check Order Total (to verify recalculation)
CURRENT_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_total'" 2>/dev/null)

# Generate JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_id": "$ORDER_ID",
    "order_status": "$ORDER_STATUS",
    "was_modified_during_task": $WAS_MODIFIED,
    "has_tshirt": $HAS_TSHIRT,
    "has_sweater": $HAS_SWEATER,
    "sweater_qty": "${SWEATER_QTY:-0}",
    "initial_total": "${INITIAL_TOTAL:-0}",
    "current_total": "${CURRENT_TOTAL:-0}",
    "items_list": [$(echo "$ORDER_ITEMS" | sed 's/^/"/;s/$/"/' | paste -sd, -)],
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json

echo "=== Export Complete ==="