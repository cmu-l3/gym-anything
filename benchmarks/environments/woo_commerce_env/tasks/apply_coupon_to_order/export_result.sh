#!/bin/bash
# Export script for Apply Coupon to Order task

echo "=== Exporting Apply Coupon to Order Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "order_found": false, "order": {}}' > /tmp/apply_coupon_to_order_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current order count
CURRENT_COUNT=$(get_order_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")

echo "Order count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Find the target order by specific attributes (coupon + customer)
# NOTE: No "newest entity" fallback - we search for orders matching the expected
# coupon (WELCOME10) and customer (john.doe@example.com) combination.
ORDER_FOUND="false"
ORDER_ID=""
ORDER_STATUS=""
ORDER_TOTAL=""
ORDER_DISCOUNT=""
ORDER_SUBTOTAL=""
ORDER_CUSTOMER_ID=""
ORDER_CUSTOMER_EMAIL=""
COUPON_APPLIED=""
LINE_ITEMS_JSON="[]"

if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    # Load pre-existing order IDs recorded at setup time to exclude them
    EXISTING_IDS=$(cat /tmp/existing_order_ids 2>/dev/null | tr -d '[:space:]')

    # Build exclusion clause (only if there are pre-existing orders)
    EXCLUDE_CLAUSE=""
    if [ -n "$EXISTING_IDS" ] && [ "$EXISTING_IDS" != "NULL" ]; then
        EXCLUDE_CLAUSE="AND p.ID NOT IN ($EXISTING_IDS)"
    fi

    # Search for NEW order with WELCOME10 coupon applied (excluding pre-existing orders)
    ORDER_ID=$(wc_query "SELECT DISTINCT oi.order_id
        FROM wp_woocommerce_order_items oi
        JOIN wp_posts p ON oi.order_id = p.ID
        WHERE oi.order_item_type = 'coupon'
        AND LOWER(oi.order_item_name) = 'welcome10'
        AND p.post_type = 'shop_order'
        AND p.post_status != 'auto-draft'
        $EXCLUDE_CLAUSE
        ORDER BY oi.order_id DESC LIMIT 1" 2>/dev/null)

    # Fallback: search by customer email among NEW orders only
    if [ -z "$ORDER_ID" ]; then
        echo "Coupon-based search failed, trying by customer email..."
        ORDER_ID=$(wc_query "SELECT p.ID
            FROM wp_posts p
            JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_customer_user'
            JOIN wp_users u ON pm.meta_value = u.ID
            WHERE p.post_type = 'shop_order'
            AND p.post_status != 'auto-draft'
            AND LOWER(u.user_email) = 'john.doe@example.com'
            $EXCLUDE_CLAUSE
            ORDER BY p.ID DESC LIMIT 1" 2>/dev/null)
    fi

    # If still not found, no fallback to "newest order"
    if [ -z "$ORDER_ID" ]; then
        echo "No matching order found by coupon or customer attributes"
    fi

    if [ -n "$ORDER_ID" ]; then
        ORDER_FOUND="true"
        ORDER_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$ORDER_ID LIMIT 1" 2>/dev/null)

        # Get order totals
        ORDER_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_total' LIMIT 1" 2>/dev/null)
        ORDER_DISCOUNT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_cart_discount' LIMIT 1" 2>/dev/null)

        # Get customer info
        ORDER_CUSTOMER_ID=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_customer_user' LIMIT 1" 2>/dev/null)
        if [ -n "$ORDER_CUSTOMER_ID" ] && [ "$ORDER_CUSTOMER_ID" != "0" ]; then
            ORDER_CUSTOMER_EMAIL=$(wc_query "SELECT user_email FROM wp_users WHERE ID=$ORDER_CUSTOMER_ID LIMIT 1" 2>/dev/null)
        fi

        # Get applied coupons
        COUPON_APPLIED=$(wc_query "SELECT GROUP_CONCAT(order_item_name SEPARATOR ',') FROM wp_woocommerce_order_items WHERE order_id=$ORDER_ID AND order_item_type='coupon'" 2>/dev/null)

        # Get line items
        LINE_ITEMS_RAW=$(wc_query "SELECT oi.order_item_name,
            MAX(CASE WHEN oim.meta_key='_qty' THEN oim.meta_value END) as qty,
            MAX(CASE WHEN oim.meta_key='_line_total' THEN oim.meta_value END) as total,
            MAX(CASE WHEN oim.meta_key='_product_id' THEN oim.meta_value END) as product_id
            FROM wp_woocommerce_order_items oi
            JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id
            WHERE oi.order_id=$ORDER_ID AND oi.order_item_type='line_item'
            GROUP BY oi.order_item_id" 2>/dev/null)

        # Build line items JSON array
        LINE_ITEMS_JSON="["
        FIRST=true
        while IFS=$'\t' read -r item_name qty total product_id; do
            [ -z "$item_name" ] && continue
            item_name_esc=$(json_escape "$item_name")
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                LINE_ITEMS_JSON="$LINE_ITEMS_JSON,"
            fi
            # Get SKU for product
            ITEM_SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$product_id AND meta_key='_sku' LIMIT 1" 2>/dev/null)
            LINE_ITEMS_JSON="$LINE_ITEMS_JSON{\"name\":\"$item_name_esc\",\"quantity\":\"$qty\",\"total\":\"$total\",\"product_id\":\"$product_id\",\"sku\":\"$ITEM_SKU\"}"
        done <<< "$LINE_ITEMS_RAW"
        LINE_ITEMS_JSON="$LINE_ITEMS_JSON]"

        # Calculate subtotal from line items
        ORDER_SUBTOTAL=$(wc_query "SELECT SUM(oim.meta_value) FROM wp_woocommerce_order_items oi JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id WHERE oi.order_id=$ORDER_ID AND oi.order_item_type='line_item' AND oim.meta_key='_line_subtotal'" 2>/dev/null)

        echo "Order found: ID=$ORDER_ID, Status=$ORDER_STATUS, Total=$ORDER_TOTAL, Discount=$ORDER_DISCOUNT, Coupon=$COUPON_APPLIED"
        echo "Customer: ID=$ORDER_CUSTOMER_ID, Email=$ORDER_CUSTOMER_EMAIL"
    fi
else
    echo "No new orders created"
fi

# Escape for JSON (handles quotes, backslashes, newlines, etc.)
COUPON_APPLIED_ESC=$(json_escape "$COUPON_APPLIED")
ORDER_CUSTOMER_EMAIL_ESC=$(json_escape "$ORDER_CUSTOMER_EMAIL")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/apply_coupon_to_order_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_order_count": ${INITIAL_COUNT:-0},
    "current_order_count": ${CURRENT_COUNT:-0},
    "order_found": $ORDER_FOUND,
    "order": {
        "id": "$ORDER_ID",
        "status": "$ORDER_STATUS",
        "total": "$ORDER_TOTAL",
        "subtotal": "$ORDER_SUBTOTAL",
        "discount": "$ORDER_DISCOUNT",
        "coupon_applied": "$COUPON_APPLIED_ESC",
        "customer_id": "$ORDER_CUSTOMER_ID",
        "customer_email": "$ORDER_CUSTOMER_EMAIL_ESC",
        "line_items": $LINE_ITEMS_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/apply_coupon_to_order_result.json

echo ""
cat /tmp/apply_coupon_to_order_result.json
echo ""
echo "=== Export Complete ==="
