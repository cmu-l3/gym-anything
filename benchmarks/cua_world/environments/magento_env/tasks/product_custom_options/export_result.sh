#!/bin/bash
# Export script for Product Custom Options task

echo "=== Exporting Product Custom Options Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TARGET_SKU="BOTTLE-001"
PRODUCT_ID=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null | cut -f1)

# Get initial counts
INITIAL_OPTION_COUNT=$(cat /tmp/initial_option_count 2>/dev/null || echo "0")
CURRENT_OPTION_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_option WHERE product_id=$PRODUCT_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Option count for $TARGET_SKU: initial=$INITIAL_OPTION_COUNT, current=$CURRENT_OPTION_COUNT"

# Retrieve the specific option created (looking for 'Laser Engraving')
# We join option, title, and price tables
OPTION_QUERY="
SELECT 
    o.option_id, 
    t.title, 
    o.type, 
    o.is_require, 
    o.sku, 
    o.max_characters, 
    p.price, 
    p.price_type,
    e.updated_at
FROM catalog_product_option o
JOIN catalog_product_entity e ON o.product_id = e.entity_id
LEFT JOIN catalog_product_option_title t ON o.option_id = t.option_id
LEFT JOIN catalog_product_option_price p ON o.option_id = p.option_id
WHERE e.sku = '$TARGET_SKU'
ORDER BY o.option_id DESC LIMIT 1
"

OPTION_DATA=$(magento_query "$OPTION_QUERY" 2>/dev/null | tail -1)

# Initialize variables
OPTION_FOUND="false"
OPT_ID=""
OPT_TITLE=""
OPT_TYPE=""
OPT_REQUIRED=""
OPT_SKU=""
OPT_MAX_CHARS=""
OPT_PRICE=""
OPT_PRICE_TYPE=""
PROD_UPDATED_AT=""

if [ -n "$OPTION_DATA" ]; then
    OPTION_FOUND="true"
    OPT_ID=$(echo "$OPTION_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    OPT_TITLE=$(echo "$OPTION_DATA" | awk -F'\t' '{print $2}')
    OPT_TYPE=$(echo "$OPTION_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    OPT_REQUIRED=$(echo "$OPTION_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    OPT_SKU=$(echo "$OPTION_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    OPT_MAX_CHARS=$(echo "$OPTION_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
    OPT_PRICE=$(echo "$OPTION_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
    OPT_PRICE_TYPE=$(echo "$OPTION_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')
    PROD_UPDATED_AT=$(echo "$OPTION_DATA" | awk -F'\t' '{print $9}')

    # Clean up price (remove trailing zeros)
    OPT_PRICE=$(echo "$OPT_PRICE" | sed 's/\.0*$//')
    # If price ends with decimal point, remove it
    OPT_PRICE=$(echo "$OPT_PRICE" | sed 's/\.$//')

    echo "Option found: ID=$OPT_ID, Title='$OPT_TITLE', Type='$OPT_TYPE', Price='$OPT_PRICE'"
else
    echo "No custom options found for $TARGET_SKU"
fi

# Escape strings for JSON
OPT_TITLE_ESC=$(echo "$OPT_TITLE" | sed 's/"/\\"/g')
OPT_SKU_ESC=$(echo "$OPT_SKU" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/custom_options_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_option_count": ${INITIAL_OPTION_COUNT:-0},
    "current_option_count": ${CURRENT_OPTION_COUNT:-0},
    "option_found": $OPTION_FOUND,
    "product_updated_at": "$PROD_UPDATED_AT",
    "option": {
        "id": "$OPT_ID",
        "title": "$OPT_TITLE_ESC",
        "type": "$OPT_TYPE",
        "is_require": "$OPT_REQUIRED",
        "sku": "$OPT_SKU_ESC",
        "max_characters": "$OPT_MAX_CHARS",
        "price": "$OPT_PRICE",
        "price_type": "$OPT_PRICE_TYPE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/custom_options_result.json

echo ""
cat /tmp/custom_options_result.json
echo ""
echo "=== Export Complete ==="