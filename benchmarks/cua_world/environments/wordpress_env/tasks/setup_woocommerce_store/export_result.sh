#!/bin/bash
# Export script for setup_woocommerce_store task (post_task hook)
# Checks WooCommerce activation, products, categories, and store settings.

echo "=== Exporting setup_woocommerce_store result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Check WooCommerce plugin status
# ============================================================
WC_ACTIVE="false"
if wp plugin is-active woocommerce --allow-root 2>/dev/null; then
    WC_ACTIVE="true"
    echo "WooCommerce is active"
else
    echo "WooCommerce is NOT active"
fi

# ============================================================
# Check store currency (only if WooCommerce is active)
# ============================================================
STORE_CURRENCY=""
if [ "$WC_ACTIVE" = "true" ]; then
    STORE_CURRENCY=$(wp_cli option get woocommerce_currency 2>/dev/null || echo "")
    echo "Store currency: $STORE_CURRENCY"
fi

# ============================================================
# Check product category 'Artisan Coffee Blends'
# ============================================================
CATEGORY_EXISTS="false"
CATEGORY_ID=""
if [ "$WC_ACTIVE" = "true" ]; then
    CATEGORY_ID=$(wp_db_query "SELECT t.term_id FROM wp_terms t
        INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE tt.taxonomy='product_cat'
        AND LOWER(TRIM(t.name)) = LOWER('Artisan Coffee Blends')
        LIMIT 1")
    if [ -n "$CATEGORY_ID" ]; then
        CATEGORY_EXISTS="true"
        echo "Product category 'Artisan Coffee Blends' found (ID: $CATEGORY_ID)"
    else
        echo "Product category 'Artisan Coffee Blends' NOT found"
    fi
fi

# ============================================================
# Check products
# ============================================================
# Expected products:
# 1. Ethiopian Yirgacheffe - $18.99 - ACB-ETH-001
# 2. Colombian Supremo - $15.49 - ACB-COL-002
# 3. Sumatra Mandheling - $16.99 - ACB-SUM-003

check_product() {
    local expected_name="$1"
    local expected_price="$2"
    local expected_sku="$3"
    local var_prefix="$4"

    local product_id=""
    local found="false"
    local price_correct="false"
    local sku_correct="false"
    local in_category="false"
    local actual_price=""
    local actual_sku=""

    # Find product by title
    product_id=$(wp_db_query "SELECT ID FROM wp_posts
        WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$expected_name'))
        AND post_type='product'
        AND post_status='publish'
        ORDER BY ID DESC LIMIT 1")

    if [ -n "$product_id" ]; then
        found="true"
        echo "Found product '$expected_name' (ID: $product_id)"

        # Check price
        actual_price=$(wp_db_query "SELECT meta_value FROM wp_postmeta
            WHERE post_id=$product_id AND meta_key='_regular_price' LIMIT 1")
        if [ "$actual_price" = "$expected_price" ]; then
            price_correct="true"
        fi
        echo "  Price: $actual_price (expected: $expected_price) - $([ "$price_correct" = "true" ] && echo OK || echo WRONG)"

        # Check SKU
        actual_sku=$(wp_db_query "SELECT meta_value FROM wp_postmeta
            WHERE post_id=$product_id AND meta_key='_sku' LIMIT 1")
        if [ "$actual_sku" = "$expected_sku" ]; then
            sku_correct="true"
        fi
        echo "  SKU: $actual_sku (expected: $expected_sku) - $([ "$sku_correct" = "true" ] && echo OK || echo WRONG)"

        # Check if in the correct category
        if [ -n "$CATEGORY_ID" ]; then
            local cat_count=$(wp_db_query "SELECT COUNT(*) FROM wp_term_relationships
                WHERE object_id=$product_id AND term_taxonomy_id IN (
                    SELECT term_taxonomy_id FROM wp_term_taxonomy
                    WHERE term_id=$CATEGORY_ID AND taxonomy='product_cat'
                )")
            if [ "$cat_count" -gt 0 ] 2>/dev/null; then
                in_category="true"
            fi
        fi
        echo "  In 'Artisan Coffee Blends': $in_category"
    else
        echo "Product '$expected_name' NOT found"
    fi

    # Output JSON fragment
    echo "{\"found\": $found, \"price_correct\": $price_correct, \"sku_correct\": $sku_correct, \"in_category\": $in_category, \"actual_price\": \"$actual_price\", \"actual_sku\": \"$actual_sku\"}"
}

PRODUCT1_JSON=$(check_product "Ethiopian Yirgacheffe" "18.99" "ACB-ETH-001" "p1")
PRODUCT2_JSON=$(check_product "Colombian Supremo" "15.49" "ACB-COL-002" "p2")
PRODUCT3_JSON=$(check_product "Sumatra Mandheling" "16.99" "ACB-SUM-003" "p3")

# Extract the JSON line (last line of check_product output)
P1_JSON=$(echo "$PRODUCT1_JSON" | tail -1)
P2_JSON=$(echo "$PRODUCT2_JSON" | tail -1)
P3_JSON=$(echo "$PRODUCT3_JSON" | tail -1)

# Total product count
TOTAL_PRODUCTS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND post_status='publish'" 2>/dev/null || echo "0")
echo ""
echo "Total published products: $TOTAL_PRODUCTS"

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "woocommerce_active": $WC_ACTIVE,
    "store_currency": "$STORE_CURRENCY",
    "category_exists": $CATEGORY_EXISTS,
    "category_id": "$CATEGORY_ID",
    "total_products": $TOTAL_PRODUCTS,
    "products": {
        "ethiopian_yirgacheffe": $P1_JSON,
        "colombian_supremo": $P2_JSON,
        "sumatra_mandheling": $P3_JSON
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/setup_woocommerce_store_result.json 2>/dev/null || sudo rm -f /tmp/setup_woocommerce_store_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/setup_woocommerce_store_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/setup_woocommerce_store_result.json
chmod 666 /tmp/setup_woocommerce_store_result.json 2>/dev/null || sudo chmod 666 /tmp/setup_woocommerce_store_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/setup_woocommerce_store_result.json"
cat /tmp/setup_woocommerce_store_result.json
echo ""
echo "=== Export complete ==="
