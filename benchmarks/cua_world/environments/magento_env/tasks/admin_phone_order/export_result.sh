#!/bin/bash
# Export script for Admin Phone Order task

echo "=== Exporting Admin Phone Order Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")
CURRENT_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")

echo "Order count: initial=$INITIAL_ORDER_COUNT, current=$CURRENT_ORDER_COUNT"

# 1. Find the most recent order for the target customer
# We join customer_entity to get the email, or check sales_order.customer_email directly
TARGET_EMAIL="alice.williams@example.com"
echo "Searching for latest order for $TARGET_EMAIL..."

ORDER_DATA=$(magento_query "SELECT entity_id, increment_id, grand_total, shipping_amount, status, created_at, customer_email, total_item_count FROM sales_order WHERE customer_email='$TARGET_EMAIL' ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)

ORDER_FOUND="false"
ORDER_ID=""
INCREMENT_ID=""
GRAND_TOTAL=""
SHIPPING_AMOUNT=""
STATUS=""
CREATED_AT=""
CUSTOMER_EMAIL=""

if [ -n "$ORDER_DATA" ]; then
    ORDER_FOUND="true"
    ORDER_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $1}')
    INCREMENT_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $2}')
    GRAND_TOTAL=$(echo "$ORDER_DATA" | awk -F'\t' '{print $3}')
    SHIPPING_AMOUNT=$(echo "$ORDER_DATA" | awk -F'\t' '{print $4}')
    STATUS=$(echo "$ORDER_DATA" | awk -F'\t' '{print $5}')
    CREATED_AT=$(echo "$ORDER_DATA" | awk -F'\t' '{print $6}')
    CUSTOMER_EMAIL=$(echo "$ORDER_DATA" | awk -F'\t' '{print $7}')
fi

echo "Order Found: $ORDER_FOUND (ID: $ORDER_ID)"

# 2. Get Order Items
ITEMS_JSON="[]"
if [ "$ORDER_FOUND" = "true" ]; then
    # Get items: sku, qty_ordered, price
    ITEMS_RAW=$(magento_query "SELECT sku, qty_ordered, price FROM sales_order_item WHERE order_id=$ORDER_ID" 2>/dev/null)
    
    # Convert raw tab-separated lines to JSON array
    if [ -n "$ITEMS_RAW" ]; then
        ITEMS_JSON=$(echo "$ITEMS_RAW" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(split("\t")) | map({"sku": .[0], "qty": .[1], "price": .[2]})')
    fi
fi

# 3. Get Shipping Address
ADDRESS_JSON="{}"
if [ "$ORDER_FOUND" = "true" ]; then
    ADDR_RAW=$(magento_query "SELECT firstname, lastname, city, region, postcode, street, telephone FROM sales_order_address WHERE parent_id=$ORDER_ID AND address_type='shipping' LIMIT 1" 2>/dev/null | tail -1)
    
    if [ -n "$ADDR_RAW" ]; then
        FIRST=$(echo "$ADDR_RAW" | awk -F'\t' '{print $1}')
        LAST=$(echo "$ADDR_RAW" | awk -F'\t' '{print $2}')
        CITY=$(echo "$ADDR_RAW" | awk -F'\t' '{print $3}')
        REGION=$(echo "$ADDR_RAW" | awk -F'\t' '{print $4}')
        POSTCODE=$(echo "$ADDR_RAW" | awk -F'\t' '{print $5}')
        STREET=$(echo "$ADDR_RAW" | awk -F'\t' '{print $6}')
        PHONE=$(echo "$ADDR_RAW" | awk -F'\t' '{print $7}')
        
        # Build JSON manually to avoid complex jq escaping issues with shell variables
        ADDRESS_JSON=$(jq -n \
            --arg first "$FIRST" \
            --arg last "$LAST" \
            --arg city "$CITY" \
            --arg region "$REGION" \
            --arg zip "$POSTCODE" \
            --arg street "$STREET" \
            --arg phone "$PHONE" \
            '{"firstname": $first, "lastname": $last, "city": $city, "region": $region, "postcode": $zip, "street": $street, "telephone": $phone}')
    fi
fi

# 4. Get Payment Method
PAYMENT_METHOD=""
if [ "$ORDER_FOUND" = "true" ]; then
    PAYMENT_METHOD=$(magento_query "SELECT method FROM sales_order_payment WHERE parent_id=$ORDER_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi

# 5. Get Order Comment
COMMENT=""
if [ "$ORDER_FOUND" = "true" ]; then
    # Check history for the specific comment
    COMMENT=$(magento_query "SELECT comment FROM sales_order_status_history WHERE parent_id=$ORDER_ID ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)
fi

# Check timestamps to prevent gaming (using pre-existing orders)
ORDER_TIMESTAMP=$(date -d "$CREATED_AT" +%s 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$ORDER_TIMESTAMP" -gt "$TASK_START_TIME" ]; then
    CREATED_DURING_TASK="true"
fi

# Construct Final JSON
TEMP_JSON=$(mktemp /tmp/order_result.XXXXXX.json)
jq -n \
    --arg found "$ORDER_FOUND" \
    --arg id "$ORDER_ID" \
    --arg increment "$INCREMENT_ID" \
    --arg total "$GRAND_TOTAL" \
    --arg shipping "$SHIPPING_AMOUNT" \
    --arg email "$CUSTOMER_EMAIL" \
    --arg payment "$PAYMENT_METHOD" \
    --arg comment "$COMMENT" \
    --argjson items "$ITEMS_JSON" \
    --argjson address "$ADDRESS_JSON" \
    --arg created_during_task "$CREATED_DURING_TASK" \
    --arg initial_count "$INITIAL_ORDER_COUNT" \
    --arg current_count "$CURRENT_ORDER_COUNT" \
    '{
        order_found: ($found == "true"),
        order_id: $id,
        increment_id: $increment,
        grand_total: $total,
        shipping_amount: $shipping,
        customer_email: $email,
        payment_method: $payment,
        comment: $comment,
        items: $items,
        shipping_address: $address,
        created_during_task: ($created_during_task == "true"),
        counts: {
            initial: $initial_count,
            current: $current_count
        }
    }' > "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/admin_order_result.json

echo "Result exported to /tmp/admin_order_result.json"
cat /tmp/admin_order_result.json
echo "=== Export Complete ==="