#!/bin/bash
echo "=== Exporting expand_product_variations result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
PROD_ID=""
BLACK_TERM_EXISTS="false"
ATTR_UPDATED="false"
VARIATION_FOUND="false"
VAR_PRICE=""
VAR_SKU=""
RED_VAR_PRICE=""
BLUE_VAR_PRICE=""

# 1. Get Product ID
PROD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='Classic T-Shirt' AND post_type='product' LIMIT 1")

if [ -n "$PROD_ID" ]; then
    # 2. Check if 'Black' term exists in pa_color taxonomy
    TERM_CHECK=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy = 'pa_color' AND t.name = 'Black'")
    if [ -n "$TERM_CHECK" ]; then
        BLACK_TERM_EXISTS="true"
    fi

    # 3. Check if Parent Product has 'Black' in attributes
    # We check the serialized string for "Black". It's a heuristic but sufficient for verification here.
    ATTR_META=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PROD_ID AND meta_key='_product_attributes'")
    if [[ "$ATTR_META" == *"Black"* ]]; then
        ATTR_UPDATED="true"
    fi

    # 4. Check for Black Variation
    # Look for child post (variation) that has meta attribute_pa_color = 'black' (slug)
    VARIATION_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_parent = $PROD_ID AND p.post_type = 'product_variation' AND pm.meta_key = 'attribute_pa_color' AND pm.meta_value = 'black' LIMIT 1")

    if [ -n "$VARIATION_ID" ]; then
        VARIATION_FOUND="true"
        VAR_PRICE=$(get_product_price $VARIATION_ID)
        VAR_SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$VARIATION_ID AND meta_key='_sku'")
    fi

    # 5. Check integrity of old variations (Red/Blue)
    RED_VAR_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_parent = $PROD_ID AND p.post_type = 'product_variation' AND pm.meta_key = 'attribute_pa_color' AND pm.meta_value = 'red' LIMIT 1")
    if [ -n "$RED_VAR_ID" ]; then
        RED_VAR_PRICE=$(get_product_price $RED_VAR_ID)
    fi
    
    BLUE_VAR_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_parent = $PROD_ID AND p.post_type = 'product_variation' AND pm.meta_key = 'attribute_pa_color' AND pm.meta_value = 'blue' LIMIT 1")
    if [ -n "$BLUE_VAR_ID" ]; then
        BLUE_VAR_PRICE=$(get_product_price $BLUE_VAR_ID)
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $([ -n "$PROD_ID" ] && echo "true" || echo "false"),
    "black_term_exists": $BLACK_TERM_EXISTS,
    "parent_attributes_updated": $ATTR_UPDATED,
    "variation_found": $VARIATION_FOUND,
    "variation_price": "${VAR_PRICE:-0}",
    "variation_sku": "${VAR_SKU:-}",
    "red_variation_price": "${RED_VAR_PRICE:-0}",
    "blue_variation_price": "${BLUE_VAR_PRICE:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json