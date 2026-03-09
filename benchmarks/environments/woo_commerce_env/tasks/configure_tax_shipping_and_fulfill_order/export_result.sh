#!/bin/bash
echo "=== Exporting Tax, Shipping, and Order Fulfillment Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/tax_shipping_order_result.json
    exit 1
fi

take_screenshot /tmp/tax_shipping_order_end_screenshot.png

TASK_START=$(cat /tmp/tax_shipping_order_start_ts 2>/dev/null || echo "0")
INITIAL_ORDER_COUNT=$(cat /tmp/tax_shipping_order_initial_count 2>/dev/null || echo "0")
EXISTING_ORDER_IDS=$(cat /tmp/tax_shipping_order_existing_ids 2>/dev/null | tr -d '[:space:]')

# ================================================================
# Check taxes enabled
# ================================================================
cd /var/www/html/wordpress 2>/dev/null || true
TAXES_ENABLED=$(wp option get woocommerce_calc_taxes --allow-root 2>/dev/null || echo "unknown")

# ================================================================
# Check CA tax rate
# ================================================================
TAX_RATE_ID=$(wc_query "SELECT tax_rate_id FROM wp_woocommerce_tax_rates WHERE tax_rate_state='CA' LIMIT 1" 2>/dev/null)
TAX_RATE_EXISTS="false"
TAX_RATE=""
TAX_RATE_NAME=""
TAX_RATE_COUNTRY=""
TAX_RATE_PRIORITY=""

if [ -n "$TAX_RATE_ID" ]; then
    TAX_RATE_EXISTS="true"
    TAX_RATE=$(wc_query "SELECT tax_rate FROM wp_woocommerce_tax_rates WHERE tax_rate_id=$TAX_RATE_ID LIMIT 1" 2>/dev/null)
    TAX_RATE_NAME=$(wc_query "SELECT tax_rate_name FROM wp_woocommerce_tax_rates WHERE tax_rate_id=$TAX_RATE_ID LIMIT 1" 2>/dev/null)
    TAX_RATE_COUNTRY=$(wc_query "SELECT tax_rate_country FROM wp_woocommerce_tax_rates WHERE tax_rate_id=$TAX_RATE_ID LIMIT 1" 2>/dev/null)
    TAX_RATE_PRIORITY=$(wc_query "SELECT tax_rate_priority FROM wp_woocommerce_tax_rates WHERE tax_rate_id=$TAX_RATE_ID LIMIT 1" 2>/dev/null)
    echo "Tax rate found: rate=$TAX_RATE, name=$TAX_RATE_NAME, country=$TAX_RATE_COUNTRY"
fi

# ================================================================
# Check California shipping zone
# ================================================================
SHIPPING_ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE LOWER(zone_name)='california' LIMIT 1" 2>/dev/null)
SHIPPING_ZONE_EXISTS="false"
SHIPPING_METHOD_EXISTS="false"
SHIPPING_METHOD_COST=""

if [ -n "$SHIPPING_ZONE_ID" ]; then
    SHIPPING_ZONE_EXISTS="true"

    # Check if zone covers California
    ZONE_LOCATION=$(wc_query "SELECT location_code FROM wp_woocommerce_shipping_zone_locations WHERE zone_id=$SHIPPING_ZONE_ID AND location_type='state' LIMIT 1" 2>/dev/null)

    # Check for flat_rate method
    FLAT_RATE_INSTANCE=$(wc_query "SELECT instance_id FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$SHIPPING_ZONE_ID AND method_id='flat_rate' AND is_enabled=1 LIMIT 1" 2>/dev/null)
    if [ -n "$FLAT_RATE_INSTANCE" ]; then
        SHIPPING_METHOD_EXISTS="true"
        # Flat rate cost is stored in wp_options as woocommerce_flat_rate_<instance_id>_settings
        SHIPPING_METHOD_COST=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_flat_rate_${FLAT_RATE_INSTANCE}_settings' LIMIT 1" 2>/dev/null)
    fi
    echo "Shipping zone: ID=$SHIPPING_ZONE_ID, location=$ZONE_LOCATION, flat_rate=$SHIPPING_METHOD_EXISTS"
fi

SHIPPING_METHOD_COST_ESC=$(json_escape "$SHIPPING_METHOD_COST")

# ================================================================
# Check order
# ================================================================
CURRENT_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")

ORDER_FOUND="false"
ORDER_ID=""
ORDER_STATUS=""
ORDER_TOTAL=""
ORDER_TAX=""
ORDER_SHIPPING_TOTAL=""
ORDER_CUSTOMER_ID=""
ORDER_CUSTOMER_EMAIL=""
ORDER_BILLING_STATE=""
ORDER_NOTE_FOUND="false"
ORDER_NOTE_TEXT=""
LINE_ITEMS_JSON="[]"

if [ "$CURRENT_ORDER_COUNT" -gt "$INITIAL_ORDER_COUNT" ]; then
    EXCLUDE_CLAUSE=""
    if [ -n "$EXISTING_ORDER_IDS" ] && [ "$EXISTING_ORDER_IDS" != "NULL" ]; then
        EXCLUDE_CLAUSE="AND p.ID NOT IN ($EXISTING_ORDER_IDS)"
    fi

    # Find order by customer email (Jane Smith)
    ORDER_ID=$(wc_query "SELECT p.ID
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_customer_user'
        JOIN wp_users u ON pm.meta_value = u.ID
        WHERE p.post_type = 'shop_order'
        AND p.post_status != 'auto-draft'
        AND LOWER(u.user_email) = 'jane.smith@example.com'
        $EXCLUDE_CLAUSE
        ORDER BY p.ID DESC LIMIT 1" 2>/dev/null)

    # Fallback: newest non-excluded order
    if [ -z "$ORDER_ID" ]; then
        ORDER_ID=$(wc_query "SELECT p.ID FROM wp_posts p
            WHERE p.post_type = 'shop_order'
            AND p.post_status != 'auto-draft'
            $EXCLUDE_CLAUSE
            ORDER BY p.ID DESC LIMIT 1" 2>/dev/null)
    fi

    if [ -n "$ORDER_ID" ]; then
        ORDER_FOUND="true"
        ORDER_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$ORDER_ID LIMIT 1" 2>/dev/null)
        ORDER_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_total' LIMIT 1" 2>/dev/null)
        ORDER_TAX=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_tax' LIMIT 1" 2>/dev/null)
        ORDER_SHIPPING_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_shipping' LIMIT 1" 2>/dev/null)
        ORDER_BILLING_STATE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_billing_state' LIMIT 1" 2>/dev/null)

        ORDER_CUSTOMER_ID=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_customer_user' LIMIT 1" 2>/dev/null)
        if [ -n "$ORDER_CUSTOMER_ID" ] && [ "$ORDER_CUSTOMER_ID" != "0" ]; then
            ORDER_CUSTOMER_EMAIL=$(wc_query "SELECT user_email FROM wp_users WHERE ID=$ORDER_CUSTOMER_ID LIMIT 1" 2>/dev/null)
        fi

        # Check for order note
        ORDER_NOTE_TEXT=$(wc_query "SELECT comment_content FROM wp_comments WHERE comment_post_ID=$ORDER_ID AND comment_type='order_note' ORDER BY comment_ID DESC LIMIT 1" 2>/dev/null)
        if [ -n "$ORDER_NOTE_TEXT" ]; then
            ORDER_NOTE_FOUND="true"
        fi

        # Get line items
        LINE_ITEMS_JSON="["
        FIRST=true
        LINE_ITEMS_RAW=$(wc_query "SELECT oi.order_item_name,
            MAX(CASE WHEN oim.meta_key='_qty' THEN oim.meta_value END) as qty,
            MAX(CASE WHEN oim.meta_key='_product_id' THEN oim.meta_value END) as product_id
            FROM wp_woocommerce_order_items oi
            JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id
            WHERE oi.order_id=$ORDER_ID AND oi.order_item_type='line_item'
            GROUP BY oi.order_item_id" 2>/dev/null)

        while IFS=$'\t' read -r item_name qty product_id; do
            [ -z "$item_name" ] && continue
            item_name_esc=$(json_escape "$item_name")
            ITEM_SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$product_id AND meta_key='_sku' LIMIT 1" 2>/dev/null)
            if [ "$FIRST" = true ]; then FIRST=false; else LINE_ITEMS_JSON="$LINE_ITEMS_JSON,"; fi
            LINE_ITEMS_JSON="$LINE_ITEMS_JSON{\"name\":\"$item_name_esc\",\"quantity\":\"$qty\",\"product_id\":\"$product_id\",\"sku\":\"$ITEM_SKU\"}"
        done <<< "$LINE_ITEMS_RAW"
        LINE_ITEMS_JSON="$LINE_ITEMS_JSON]"

        echo "Order: ID=$ORDER_ID, Status=$ORDER_STATUS, Total=$ORDER_TOTAL, Tax=$ORDER_TAX, Shipping=$ORDER_SHIPPING_TOTAL"
        echo "Customer: $ORDER_CUSTOMER_EMAIL, Billing state: $ORDER_BILLING_STATE"
        echo "Note: $ORDER_NOTE_TEXT"
    fi
fi

ORDER_CUSTOMER_EMAIL_ESC=$(json_escape "$ORDER_CUSTOMER_EMAIL")
ORDER_NOTE_TEXT_ESC=$(json_escape "$ORDER_NOTE_TEXT")
TAX_RATE_NAME_ESC=$(json_escape "$TAX_RATE_NAME")
ZONE_LOCATION_ESC=$(json_escape "${ZONE_LOCATION:-}")

TEMP_JSON=$(mktemp /tmp/tax_shipping_order_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "taxes_enabled": "$TAXES_ENABLED",
    "tax_rate_exists": $TAX_RATE_EXISTS,
    "tax_rate": {
        "rate": "$TAX_RATE",
        "name": "$TAX_RATE_NAME_ESC",
        "country": "$TAX_RATE_COUNTRY",
        "state": "CA",
        "priority": "$TAX_RATE_PRIORITY"
    },
    "shipping_zone_exists": $SHIPPING_ZONE_EXISTS,
    "shipping_zone": {
        "id": "$SHIPPING_ZONE_ID",
        "location": "$ZONE_LOCATION_ESC",
        "flat_rate_exists": $SHIPPING_METHOD_EXISTS,
        "flat_rate_settings": "$SHIPPING_METHOD_COST_ESC"
    },
    "initial_order_count": $INITIAL_ORDER_COUNT,
    "current_order_count": $CURRENT_ORDER_COUNT,
    "order_found": $ORDER_FOUND,
    "order": {
        "id": "$ORDER_ID",
        "status": "$ORDER_STATUS",
        "total": "$ORDER_TOTAL",
        "tax": "$ORDER_TAX",
        "shipping_total": "$ORDER_SHIPPING_TOTAL",
        "customer_email": "$ORDER_CUSTOMER_EMAIL_ESC",
        "billing_state": "$ORDER_BILLING_STATE",
        "note_found": $ORDER_NOTE_FOUND,
        "note_text": "$ORDER_NOTE_TEXT_ESC",
        "line_items": $LINE_ITEMS_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/tax_shipping_order_result.json

echo ""
cat /tmp/tax_shipping_order_result.json
echo ""
echo "=== Export Complete ==="
