#!/bin/bash
echo "=== Exporting Launch Coffee Product Line Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable", "product_found": false, "coupon_found": false, "order_found": false}' > /tmp/launch_coffee_result.json
    exit 1
fi

take_screenshot /tmp/launch_coffee_end_screenshot.png

TASK_START=$(cat /tmp/launch_coffee_start_ts 2>/dev/null || echo "0")
EXISTING_ORDER_IDS=$(cat /tmp/launch_coffee_existing_order_ids 2>/dev/null | tr -d '[:space:]')

# ================================================================
# Check categories
# ================================================================
ARTISAN_CAT_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(TRIM(t.name))='artisan coffee' LIMIT 1" 2>/dev/null)
ARTISAN_CAT_EXISTS="false"
[ -n "$ARTISAN_CAT_ID" ] && ARTISAN_CAT_EXISTS="true"

SINGLE_ORIGIN_CAT_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(TRIM(t.name))='single origin' LIMIT 1" 2>/dev/null)
SINGLE_ORIGIN_EXISTS="false"
SINGLE_ORIGIN_PARENT=""
SINGLE_ORIGIN_IS_CHILD="false"

if [ -n "$SINGLE_ORIGIN_CAT_ID" ]; then
    SINGLE_ORIGIN_EXISTS="true"
    SINGLE_ORIGIN_PARENT=$(wc_query "SELECT tt.parent FROM wp_term_taxonomy tt WHERE tt.term_id=$SINGLE_ORIGIN_CAT_ID AND tt.taxonomy='product_cat' LIMIT 1" 2>/dev/null)
    if [ -n "$ARTISAN_CAT_ID" ] && [ "$SINGLE_ORIGIN_PARENT" = "$ARTISAN_CAT_ID" ]; then
        SINGLE_ORIGIN_IS_CHILD="true"
    fi
fi

echo "Categories: Artisan Coffee=$ARTISAN_CAT_EXISTS (ID=$ARTISAN_CAT_ID), Single Origin=$SINGLE_ORIGIN_EXISTS (parent=$SINGLE_ORIGIN_PARENT, is_child=$SINGLE_ORIGIN_IS_CHILD)"

# ================================================================
# Check product
# ================================================================
PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='EYC-001' LIMIT 1" 2>/dev/null)
PRODUCT_FOUND="false"
PRODUCT_NAME=""
PRODUCT_STATUS=""
PRODUCT_TYPE_TERM=""
PRODUCT_CATEGORIES=""
CROSS_SELL_IDS=""
SHIPPING_CLASS_PRODUCT=""
VARIATIONS_JSON="[]"

if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_NAME=$(wc_query "SELECT post_title FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1" 2>/dev/null)
    PRODUCT_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1" 2>/dev/null)

    # Product type
    PRODUCT_TYPE_TERM=$(wc_query "SELECT t.name FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_type' LIMIT 1" 2>/dev/null)

    # Categories
    PRODUCT_CATEGORIES=$(wc_query "SELECT GROUP_CONCAT(t.name SEPARATOR ',') FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_cat'" 2>/dev/null)

    # Cross-sells
    CROSS_SELL_IDS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_crosssell_ids' LIMIT 1" 2>/dev/null)

    # Shipping class
    SHIPPING_CLASS_PRODUCT=$(wc_query "SELECT t.name FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_shipping_class' LIMIT 1" 2>/dev/null)

    # Variations
    VARIATIONS_JSON="["
    FIRST=true
    VARIATION_DATA=$(wc_query "SELECT p.ID,
        MAX(CASE WHEN pm.meta_key='_regular_price' THEN pm.meta_value END) as price,
        MAX(CASE WHEN pm.meta_key='_stock' THEN pm.meta_value END) as stock,
        MAX(CASE WHEN pm.meta_key='_manage_stock' THEN pm.meta_value END) as manage_stock,
        MAX(CASE WHEN pm.meta_key='_stock_status' THEN pm.meta_value END) as stock_status
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id
        WHERE p.post_parent=$PRODUCT_ID AND p.post_type='product_variation'
        GROUP BY p.ID" 2>/dev/null)

    while IFS=$'\t' read -r var_id var_price var_stock var_manage var_stock_status; do
        [ -z "$var_id" ] && continue

        # Get variation attributes - try both global (pa_) and custom attribute prefixes
        VAR_ROAST=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$var_id AND (meta_key='attribute_pa_roast-level' OR meta_key='attribute_roast-level' OR meta_key='attribute_pa_roast_level' OR meta_key='attribute_roast_level' OR meta_key LIKE 'attribute_%roast%') LIMIT 1" 2>/dev/null)
        VAR_SIZE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$var_id AND (meta_key='attribute_pa_size' OR meta_key='attribute_size' OR meta_key LIKE 'attribute_%size%') LIMIT 1" 2>/dev/null)

        VAR_ROAST_ESC=$(json_escape "$VAR_ROAST")
        VAR_SIZE_ESC=$(json_escape "$VAR_SIZE")

        if [ "$FIRST" = true ]; then FIRST=false; else VARIATIONS_JSON="$VARIATIONS_JSON,"; fi
        VARIATIONS_JSON="$VARIATIONS_JSON{\"id\":\"$var_id\",\"roast_level\":\"$VAR_ROAST_ESC\",\"size\":\"$VAR_SIZE_ESC\",\"price\":\"$var_price\",\"stock\":\"$var_stock\",\"manage_stock\":\"$var_manage\",\"stock_status\":\"$var_stock_status\"}"
    done <<< "$VARIATION_DATA"
    VARIATIONS_JSON="$VARIATIONS_JSON]"

    echo "Product found: ID=$PRODUCT_ID, Name=$PRODUCT_NAME, Type=$PRODUCT_TYPE_TERM, Status=$PRODUCT_STATUS"
    echo "Categories: $PRODUCT_CATEGORIES"
    echo "Shipping class: $SHIPPING_CLASS_PRODUCT"
fi

# Check cross-sell contains OCT-BLK-M
OCT_PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='OCT-BLK-M' LIMIT 1" 2>/dev/null)
CROSS_SELL_CONTAINS_OCT="false"
if [ -n "$CROSS_SELL_IDS" ] && [ -n "$OCT_PRODUCT_ID" ]; then
    if echo "$CROSS_SELL_IDS" | grep -q "$OCT_PRODUCT_ID"; then
        CROSS_SELL_CONTAINS_OCT="true"
    fi
fi

# ================================================================
# Check shipping class
# ================================================================
SHIPPING_CLASS_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_shipping_class' AND (LOWER(t.name)='fragile items' OR t.slug='fragile-items') LIMIT 1" 2>/dev/null)
SHIPPING_CLASS_EXISTS="false"
SHIPPING_CLASS_SLUG=""
SHIPPING_CLASS_DESC=""

if [ -n "$SHIPPING_CLASS_ID" ]; then
    SHIPPING_CLASS_EXISTS="true"
    SHIPPING_CLASS_SLUG=$(wc_query "SELECT t.slug FROM wp_terms t WHERE t.term_id=$SHIPPING_CLASS_ID LIMIT 1" 2>/dev/null)
    SHIPPING_CLASS_DESC=$(wc_query "SELECT tt.description FROM wp_term_taxonomy tt WHERE tt.term_id=$SHIPPING_CLASS_ID AND tt.taxonomy='product_shipping_class' LIMIT 1" 2>/dev/null)
fi

echo "Shipping class: exists=$SHIPPING_CLASS_EXISTS, slug=$SHIPPING_CLASS_SLUG"

# ================================================================
# Check coupon
# ================================================================
COUPON_FOUND="false"
COUPON_ID=""
COUPON_TYPE=""
COUPON_AMOUNT=""
COUPON_MIN_SPEND=""
COUPON_USAGE_LIMIT=""
COUPON_EXPIRY=""
COUPON_CAT_IDS_RAW=""

COUPON_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='shop_coupon' AND LOWER(post_title)='coffee15' AND post_status='publish' LIMIT 1" 2>/dev/null)

if [ -n "$COUPON_ID" ]; then
    COUPON_FOUND="true"
    COUPON_TYPE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='discount_type' LIMIT 1" 2>/dev/null)
    COUPON_AMOUNT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='coupon_amount' LIMIT 1" 2>/dev/null)
    COUPON_MIN_SPEND=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='minimum_amount' LIMIT 1" 2>/dev/null)
    COUPON_USAGE_LIMIT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='usage_limit' LIMIT 1" 2>/dev/null)
    COUPON_EXPIRY=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='date_expires' LIMIT 1" 2>/dev/null)
    if [ -z "$COUPON_EXPIRY" ]; then
        COUPON_EXPIRY=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='expiry_date' LIMIT 1" 2>/dev/null)
    fi
    COUPON_CAT_IDS_RAW=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='product_categories' LIMIT 1" 2>/dev/null)

    echo "Coupon COFFEE15: type=$COUPON_TYPE, amount=$COUPON_AMOUNT, min=$COUPON_MIN_SPEND, limit=$COUPON_USAGE_LIMIT, expiry=$COUPON_EXPIRY"
fi

# ================================================================
# Check order
# ================================================================
# Use HPOS tables (wp_wc_orders) since WooCommerce has custom orders table enabled
EXCLUDE_CLAUSE=""
if [ -n "$EXISTING_ORDER_IDS" ] && [ "$EXISTING_ORDER_IDS" != "NULL" ]; then
    EXCLUDE_CLAUSE="AND o.id NOT IN ($EXISTING_ORDER_IDS)"
fi

ORDER_FOUND="false"
ORDER_ID=""
ORDER_STATUS=""
ORDER_TOTAL=""
ORDER_EMAIL=""
ORDER_NOTE=""
ORDER_BILLING_STATE=""
ORDER_ITEMS="[]"

# Find order for emily.chen@example.com using HPOS tables
EMILY_ID=$(wc_query "SELECT ID FROM wp_users WHERE LOWER(user_email)='emily.chen@example.com' LIMIT 1" 2>/dev/null)
if [ -n "$EMILY_ID" ]; then
    ORDER_ID=$(wc_query "SELECT o.id
        FROM wp_wc_orders o
        WHERE o.type = 'shop_order'
        AND o.status != 'auto-draft'
        AND o.customer_id = '$EMILY_ID'
        $EXCLUDE_CLAUSE
        ORDER BY o.id DESC LIMIT 1" 2>/dev/null)
fi

if [ -n "$ORDER_ID" ]; then
    ORDER_FOUND="true"
    # Get order details from HPOS tables
    ORDER_STATUS=$(wc_query "SELECT status FROM wp_wc_orders WHERE id=$ORDER_ID" 2>/dev/null)
    ORDER_TOTAL=$(wc_query "SELECT total_amount FROM wp_wc_orders WHERE id=$ORDER_ID" 2>/dev/null)
    ORDER_EMAIL=$(wc_query "SELECT billing_email FROM wp_wc_orders WHERE id=$ORDER_ID" 2>/dev/null)
    # Get billing state from wp_wc_order_addresses
    ORDER_BILLING_STATE=$(wc_query "SELECT state FROM wp_wc_order_addresses WHERE order_id=$ORDER_ID AND address_type='billing' LIMIT 1" 2>/dev/null)

    # Get order note (still in wp_comments)
    ORDER_NOTE=$(wc_query "SELECT comment_content FROM wp_comments WHERE comment_post_ID=$ORDER_ID AND comment_type='order_note' AND comment_agent='system' ORDER BY comment_ID DESC LIMIT 1" 2>/dev/null)
    if [ -z "$ORDER_NOTE" ]; then
        ORDER_NOTE=$(wc_query "SELECT comment_content FROM wp_comments WHERE comment_post_ID=$ORDER_ID AND comment_type='order_note' ORDER BY comment_ID DESC LIMIT 1" 2>/dev/null)
    fi

    # Get line items (wp_woocommerce_order_items is still used with HPOS)
    ORDER_ITEMS="["
    FIRST=true
    ITEMS_RAW=$(wc_query "SELECT oi.order_item_name,
        MAX(CASE WHEN oim.meta_key='_qty' THEN oim.meta_value END) as qty,
        MAX(CASE WHEN oim.meta_key='_product_id' THEN oim.meta_value END) as pid,
        MAX(CASE WHEN oim.meta_key='_variation_id' THEN oim.meta_value END) as vid
        FROM wp_woocommerce_order_items oi
        JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id
        WHERE oi.order_id=$ORDER_ID AND oi.order_item_type='line_item'
        GROUP BY oi.order_item_id" 2>/dev/null)

    while IFS=$'\t' read -r iname iqty ipid ivid; do
        [ -z "$iname" ] && continue
        local_sku=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ipid AND meta_key='_sku' LIMIT 1" 2>/dev/null)
        iname_esc=$(json_escape "$iname")
        if [ "$FIRST" = true ]; then FIRST=false; else ORDER_ITEMS="$ORDER_ITEMS,"; fi
        ORDER_ITEMS="$ORDER_ITEMS{\"name\":\"$iname_esc\",\"quantity\":\"$iqty\",\"sku\":\"$local_sku\",\"variation_id\":\"$ivid\"}"
    done <<< "$ITEMS_RAW"
    ORDER_ITEMS="$ORDER_ITEMS]"

    echo "Order: ID=$ORDER_ID, Status=$ORDER_STATUS, Email=$ORDER_EMAIL, State=$ORDER_BILLING_STATE"
fi

# ================================================================
# Build result JSON
# ================================================================
PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")
PRODUCT_CATEGORIES_ESC=$(json_escape "$PRODUCT_CATEGORIES")
CROSS_SELL_IDS_ESC=$(json_escape "$CROSS_SELL_IDS")
SHIPPING_CLASS_PRODUCT_ESC=$(json_escape "$SHIPPING_CLASS_PRODUCT")
SHIPPING_CLASS_DESC_ESC=$(json_escape "$SHIPPING_CLASS_DESC")
COUPON_EXPIRY_ESC=$(json_escape "$COUPON_EXPIRY")
COUPON_CAT_IDS_ESC=$(json_escape "$COUPON_CAT_IDS_RAW")
ORDER_NOTE_ESC=$(json_escape "$ORDER_NOTE")
ORDER_EMAIL_ESC=$(json_escape "$ORDER_EMAIL")

TEMP_JSON=$(mktemp /tmp/launch_coffee_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "categories": {
        "artisan_coffee_exists": $ARTISAN_CAT_EXISTS,
        "artisan_coffee_id": "$ARTISAN_CAT_ID",
        "single_origin_exists": $SINGLE_ORIGIN_EXISTS,
        "single_origin_id": "$SINGLE_ORIGIN_CAT_ID",
        "single_origin_is_child_of_artisan": $SINGLE_ORIGIN_IS_CHILD
    },
    "product": {
        "found": $PRODUCT_FOUND,
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "status": "$PRODUCT_STATUS",
        "type": "$PRODUCT_TYPE_TERM",
        "categories": "$PRODUCT_CATEGORIES_ESC",
        "cross_sell_ids_raw": "$CROSS_SELL_IDS_ESC",
        "cross_sell_contains_oct": $CROSS_SELL_CONTAINS_OCT,
        "shipping_class": "$SHIPPING_CLASS_PRODUCT_ESC"
    },
    "variations": $VARIATIONS_JSON,
    "shipping_class": {
        "exists": $SHIPPING_CLASS_EXISTS,
        "slug": "$SHIPPING_CLASS_SLUG",
        "description": "$SHIPPING_CLASS_DESC_ESC"
    },
    "coupon": {
        "found": $COUPON_FOUND,
        "id": "$COUPON_ID",
        "discount_type": "$COUPON_TYPE",
        "amount": "$COUPON_AMOUNT",
        "minimum_amount": "$COUPON_MIN_SPEND",
        "usage_limit": "$COUPON_USAGE_LIMIT",
        "expiry": "$COUPON_EXPIRY_ESC",
        "product_category_ids_raw": "$COUPON_CAT_IDS_ESC"
    },
    "order": {
        "found": $ORDER_FOUND,
        "id": "$ORDER_ID",
        "status": "$ORDER_STATUS",
        "total": "$ORDER_TOTAL",
        "customer_email": "$ORDER_EMAIL_ESC",
        "billing_state": "$ORDER_BILLING_STATE",
        "note": "$ORDER_NOTE_ESC",
        "line_items": ${ORDER_ITEMS:-[]}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/launch_coffee_result.json

echo ""
cat /tmp/launch_coffee_result.json
echo ""
echo "=== Export Complete ==="
