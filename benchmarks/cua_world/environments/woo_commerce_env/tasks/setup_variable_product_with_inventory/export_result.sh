#!/bin/bash
echo "=== Exporting Variable Product with Inventory Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable", "product_found": false}' > /tmp/setup_variable_product_result.json
    exit 1
fi

take_screenshot /tmp/setup_variable_product_end_screenshot.png

TASK_START=$(cat /tmp/setup_variable_product_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/setup_variable_product_initial_count 2>/dev/null || echo "0")
INITIAL_VAR_COUNT=$(cat /tmp/setup_variable_product_initial_variation_count 2>/dev/null || echo "0")

CURRENT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND post_status='publish'" 2>/dev/null || echo "0")
CURRENT_VAR_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product_variation'" 2>/dev/null || echo "0")

# ================================================================
# Find the product by SKU
# ================================================================
PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='PMWS-001' LIMIT 1" 2>/dev/null)
PRODUCT_FOUND="false"
PRODUCT_NAME=""
PRODUCT_STATUS=""
PRODUCT_TYPE_TERM=""
PRODUCT_CATEGORIES=""
CROSS_SELL_IDS=""
ATTRIBUTES_RAW=""
VARIATIONS_JSON="[]"

if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_NAME=$(wc_query "SELECT post_title FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1" 2>/dev/null)
    PRODUCT_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1" 2>/dev/null)

    # Get product type from taxonomy
    PRODUCT_TYPE_TERM=$(wc_query "SELECT t.name FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_type' LIMIT 1" 2>/dev/null)

    # Get product categories
    PRODUCT_CATEGORIES=$(wc_query "SELECT GROUP_CONCAT(t.name SEPARATOR ',') FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_cat'" 2>/dev/null)

    # Get cross-sell IDs (stored as serialized PHP array)
    CROSS_SELL_IDS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_crosssell_ids' LIMIT 1" 2>/dev/null)

    # Get product attributes (serialized PHP array)
    ATTRIBUTES_RAW=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_product_attributes' LIMIT 1" 2>/dev/null)

    # Get variations
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

        # Get variation attributes (e.g., attribute_pa_color, attribute_pa_size or attribute_color, attribute_size)
        VAR_COLOR=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$var_id AND (meta_key='attribute_pa_color' OR meta_key='attribute_color') LIMIT 1" 2>/dev/null)
        VAR_SIZE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$var_id AND (meta_key='attribute_pa_size' OR meta_key='attribute_size') LIMIT 1" 2>/dev/null)

        VAR_COLOR_ESC=$(json_escape "$VAR_COLOR")
        VAR_SIZE_ESC=$(json_escape "$VAR_SIZE")

        if [ "$FIRST" = true ]; then FIRST=false; else VARIATIONS_JSON="$VARIATIONS_JSON,"; fi
        VARIATIONS_JSON="$VARIATIONS_JSON{\"id\":\"$var_id\",\"color\":\"$VAR_COLOR_ESC\",\"size\":\"$VAR_SIZE_ESC\",\"price\":\"$var_price\",\"stock\":\"$var_stock\",\"manage_stock\":\"$var_manage\",\"stock_status\":\"$var_stock_status\"}"
    done <<< "$VARIATION_DATA"
    VARIATIONS_JSON="$VARIATIONS_JSON]"

    echo "Product found: ID=$PRODUCT_ID, Name=$PRODUCT_NAME, Type=$PRODUCT_TYPE_TERM, Status=$PRODUCT_STATUS"
    echo "Categories: $PRODUCT_CATEGORIES"
    echo "Cross-sells raw: $CROSS_SELL_IDS"
fi

# Check if the cross-sell target (Merino Wool Sweater) ID is in the cross-sell list
MWS_PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='MWS-GRY-L' LIMIT 1" 2>/dev/null)
CROSS_SELL_CONTAINS_MWS="false"
if [ -n "$CROSS_SELL_IDS" ] && [ -n "$MWS_PRODUCT_ID" ]; then
    if echo "$CROSS_SELL_IDS" | grep -q "$MWS_PRODUCT_ID"; then
        CROSS_SELL_CONTAINS_MWS="true"
    fi
fi

PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")
PRODUCT_CATEGORIES_ESC=$(json_escape "$PRODUCT_CATEGORIES")
CROSS_SELL_IDS_ESC=$(json_escape "$CROSS_SELL_IDS")
ATTRIBUTES_RAW_ESC=$(json_escape "$ATTRIBUTES_RAW")

TEMP_JSON=$(mktemp /tmp/setup_variable_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_product_count": $INITIAL_COUNT,
    "current_product_count": $CURRENT_COUNT,
    "initial_variation_count": $INITIAL_VAR_COUNT,
    "current_variation_count": $CURRENT_VAR_COUNT,
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "status": "$PRODUCT_STATUS",
        "type": "$PRODUCT_TYPE_TERM",
        "categories": "$PRODUCT_CATEGORIES_ESC",
        "cross_sell_ids_raw": "$CROSS_SELL_IDS_ESC",
        "cross_sell_contains_mws": $CROSS_SELL_CONTAINS_MWS,
        "attributes_raw": "$ATTRIBUTES_RAW_ESC"
    },
    "variations": $VARIATIONS_JSON,
    "mws_product_id": "$MWS_PRODUCT_ID",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/setup_variable_product_result.json

echo ""
cat /tmp/setup_variable_product_result.json
echo ""
echo "=== Export Complete ==="
