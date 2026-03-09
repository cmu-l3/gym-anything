#!/bin/bash
echo "=== Exporting Configure Seasonal Flash Sale Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable", "flash_sale_category_exists": false, "coupon_found": false}' > /tmp/configure_seasonal_flash_sale_result.json
    exit 1
fi

take_screenshot /tmp/configure_seasonal_flash_sale_end_screenshot.png

TASK_START=$(cat /tmp/configure_seasonal_flash_sale_start_ts 2>/dev/null || echo "0")
EXISTING_COUPON_IDS=$(cat /tmp/configure_seasonal_flash_sale_existing_coupon_ids 2>/dev/null | tr -d '[:space:]')

# ================================================================
# Check for "Flash Sale" category
# ================================================================
FLASH_CAT_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)='flash sale' LIMIT 1" 2>/dev/null)
FLASH_CAT_EXISTS="false"
FLASH_CAT_TERM_TAX_ID=""
if [ -n "$FLASH_CAT_ID" ]; then
    FLASH_CAT_EXISTS="true"
    FLASH_CAT_TERM_TAX_ID=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$FLASH_CAT_ID AND taxonomy='product_cat' LIMIT 1" 2>/dev/null)
fi

echo "Flash Sale category: exists=$FLASH_CAT_EXISTS, term_id=$FLASH_CAT_ID, tt_id=$FLASH_CAT_TERM_TAX_ID"

# ================================================================
# Check each target product's sale price and Flash Sale membership
# ================================================================
PRODUCTS_JSON="["
FIRST=true
for SKU in "WBH-001" "YMP-001" "LED-DL-01"; do
    PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$SKU' LIMIT 1" 2>/dev/null)
    PRODUCT_NAME=$(wc_query "SELECT post_title FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1" 2>/dev/null)
    SALE_PRICE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price' LIMIT 1" 2>/dev/null)

    # Check membership in Flash Sale category
    IN_FLASH_CAT="false"
    if [ -n "$FLASH_CAT_TERM_TAX_ID" ] && [ -n "$PRODUCT_ID" ]; then
        IN_CAT=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$PRODUCT_ID AND term_taxonomy_id=$FLASH_CAT_TERM_TAX_ID" 2>/dev/null)
        [ "$IN_CAT" -gt 0 ] 2>/dev/null && IN_FLASH_CAT="true"
    fi

    PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")

    if [ "$FIRST" = true ]; then FIRST=false; else PRODUCTS_JSON="$PRODUCTS_JSON,"; fi
    PRODUCTS_JSON="$PRODUCTS_JSON{\"sku\":\"$SKU\",\"name\":\"$PRODUCT_NAME_ESC\",\"product_id\":\"$PRODUCT_ID\",\"sale_price\":\"$SALE_PRICE\",\"in_flash_sale_category\":$IN_FLASH_CAT}"
    echo "Product $SKU: sale_price=$SALE_PRICE, in_flash_cat=$IN_FLASH_CAT"
done
PRODUCTS_JSON="$PRODUCTS_JSON]"

# ================================================================
# Check for FLASH30 coupon
# ================================================================
COUPON_FOUND="false"
COUPON_ID=""
COUPON_TYPE=""
COUPON_AMOUNT=""
COUPON_MIN_SPEND=""
COUPON_USAGE_LIMIT=""
COUPON_EXPIRY=""
COUPON_CAT_IDS_RAW=""

COUPON_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='shop_coupon' AND LOWER(post_title)='flash30' AND post_status='publish' LIMIT 1" 2>/dev/null)

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

    echo "Coupon FLASH30: type=$COUPON_TYPE, amount=$COUPON_AMOUNT, min=$COUPON_MIN_SPEND, limit=$COUPON_USAGE_LIMIT, expiry=$COUPON_EXPIRY"
    echo "Coupon category restriction raw: $COUPON_CAT_IDS_RAW"
fi

COUPON_EXPIRY_ESC=$(json_escape "$COUPON_EXPIRY")
COUPON_CAT_IDS_ESC=$(json_escape "$COUPON_CAT_IDS_RAW")

TEMP_JSON=$(mktemp /tmp/configure_seasonal_flash_sale_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "flash_sale_category_exists": $FLASH_CAT_EXISTS,
    "flash_sale_category_id": "$FLASH_CAT_ID",
    "products": $PRODUCTS_JSON,
    "coupon_found": $COUPON_FOUND,
    "coupon": {
        "id": "$COUPON_ID",
        "discount_type": "$COUPON_TYPE",
        "amount": "$COUPON_AMOUNT",
        "minimum_amount": "$COUPON_MIN_SPEND",
        "usage_limit": "$COUPON_USAGE_LIMIT",
        "expiry": "$COUPON_EXPIRY_ESC",
        "product_category_ids_raw": "$COUPON_CAT_IDS_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_seasonal_flash_sale_result.json

echo ""
cat /tmp/configure_seasonal_flash_sale_result.json
echo ""
echo "=== Export Complete ==="
