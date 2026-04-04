#!/bin/bash
# Export script for Create Manual Order task

echo "=== Exporting Create Manual Order Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_order_count 2>/dev/null || echo "0")
ORDER_CREATED="false"

# 3. Find the Target Order
# Logic: Look for the NEWEST order created AFTER task start.
# We join posts with postmeta to filter by creation time more reliably if needed,
# but using ID DESC on new items is usually sufficient in a single-agent env.

echo "Searching for new order..."

# Get the most recent shop_order
LATEST_ORDER_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='shop_order' AND post_status != 'auto-draft' ORDER BY ID DESC LIMIT 1")

ORDER_DATA="{}"

if [ -n "$LATEST_ORDER_ID" ]; then
    # Check if this order is actually new (ID > some threshold or Count increased)
    # Since IDs increment, we can just check if count increased.
    # However, to be robust against "delete then create", we check the post_date or if we had a baseline ID.
    # For now, we trust the timestamp check in the SQL query.
    
    # Get Order Timestamp
    ORDER_DATE_STR=$(wc_query "SELECT post_date FROM wp_posts WHERE ID=$LATEST_ORDER_ID")
    ORDER_TIMESTAMP=$(date -d "$ORDER_DATE_STR" +%s)
    
    if [ "$ORDER_TIMESTAMP" -ge "$TASK_START" ]; then
        ORDER_CREATED="true"
        echo "Found new order ID: $LATEST_ORDER_ID created at $ORDER_DATE_STR"
        
        # Extract Order Status
        ORDER_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$LATEST_ORDER_ID")
        
        # Extract Order Total
        ORDER_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_order_total'")
        
        # Extract Payment Method Title
        PAYMENT_TITLE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_payment_method_title'")
        
        # Extract Billing Info
        BILLING_FIRST=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_first_name'")
        BILLING_LAST=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_last_name'")
        BILLING_ADD1=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_address_1'")
        BILLING_CITY=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_city'")
        BILLING_STATE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_state'")
        BILLING_POSTCODE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_postcode'")
        BILLING_EMAIL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_email'")
        BILLING_PHONE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$LATEST_ORDER_ID AND meta_key='_billing_phone'")
        
        # Extract Line Items
        # This requires a more complex join.
        # Format: SKU:QTY,SKU:QTY
        LINE_ITEMS_JSON="["
        
        # Get line item IDs
        ITEM_IDS=$(wc_query "SELECT order_item_id FROM wp_woocommerce_order_items WHERE order_id=$LATEST_ORDER_ID AND order_item_type='line_item'")
        
        FIRST_ITEM=true
        for ITEM_ID in $ITEM_IDS; do
            # Get Product ID and Qty for this item
            PROD_ID=$(wc_query "SELECT meta_value FROM wp_woocommerce_order_itemmeta WHERE order_item_id=$ITEM_ID AND meta_key='_product_id'")
            QTY=$(wc_query "SELECT meta_value FROM wp_woocommerce_order_itemmeta WHERE order_item_id=$ITEM_ID AND meta_key='_qty'")
            
            # Get SKU from Product ID
            SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PROD_ID AND meta_key='_sku'")
            
            if [ "$FIRST_ITEM" = true ]; then
                FIRST_ITEM=false
            else
                LINE_ITEMS_JSON="$LINE_ITEMS_JSON,"
            fi
            
            LINE_ITEMS_JSON="${LINE_ITEMS_JSON} {\"sku\": \"$SKU\", \"qty\": $QTY}"
        done
        LINE_ITEMS_JSON="$LINE_ITEMS_JSON ]"
        
        # Build JSON object
        ORDER_DATA="{
            \"id\": \"$LATEST_ORDER_ID\",
            \"status\": \"$ORDER_STATUS\",
            \"total\": \"$ORDER_TOTAL\",
            \"payment_method_title\": \"$(json_escape "$PAYMENT_TITLE")\",
            \"billing\": {
                \"first_name\": \"$(json_escape "$BILLING_FIRST")\",
                \"last_name\": \"$(json_escape "$BILLING_LAST")\",
                \"address_1\": \"$(json_escape "$BILLING_ADD1")\",
                \"city\": \"$(json_escape "$BILLING_CITY")\",
                \"state\": \"$(json_escape "$BILLING_STATE")\",
                \"postcode\": \"$(json_escape "$BILLING_POSTCODE")\",
                \"email\": \"$(json_escape "$BILLING_EMAIL")\",
                \"phone\": \"$(json_escape "$BILLING_PHONE")\"
            },
            \"line_items\": $LINE_ITEMS_JSON
        }"
    else
        echo "Latest order is old. No new order created."
    fi
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/order_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_created": $ORDER_CREATED,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "order_data": $ORDER_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="