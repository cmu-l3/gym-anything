#!/bin/bash
# Export script for Configurable Product task

echo "=== Exporting Configurable Product Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Read initial counts
INITIAL_ATTR_COUNT=$(cat /tmp/initial_attr_count 2>/dev/null || echo "0")
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")
INITIAL_LINK_COUNT=$(cat /tmp/initial_link_count 2>/dev/null || echo "0")

# ==============================================================================
# 1. VERIFY ATTRIBUTE ('shirt_color')
# ==============================================================================
echo "Checking attribute 'shirt_color'..."
ATTR_DATA=$(magento_query "SELECT attribute_id, frontend_input, is_user_defined FROM eav_attribute WHERE attribute_code='shirt_color' AND entity_type_id=4" 2>/dev/null | tail -1)
ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ATTR_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

ATTR_FOUND="false"
[ -n "$ATTR_ID" ] && ATTR_FOUND="true"

# Check options (White, Blue, Black)
OPTIONS_FOUND_COUNT=0
OPTIONS_LIST=""
if [ -n "$ATTR_ID" ]; then
    # Get values from eav_attribute_option_value for this attribute
    # We join with eav_attribute_option to filter by attribute_id
    RAW_OPTIONS=$(magento_query "SELECT v.value FROM eav_attribute_option_value v 
        JOIN eav_attribute_option o ON v.option_id = o.option_id 
        WHERE o.attribute_id = $ATTR_ID AND v.store_id = 0" 2>/dev/null)
    
    OPTIONS_LIST=$(echo "$RAW_OPTIONS" | tr '\n' ',' | sed 's/,$//')
    
    # Check for specific expected values (case-insensitive)
    if echo "$RAW_OPTIONS" | grep -qi "White"; then ((OPTIONS_FOUND_COUNT++)); fi
    if echo "$RAW_OPTIONS" | grep -qi "Blue"; then ((OPTIONS_FOUND_COUNT++)); fi
    if echo "$RAW_OPTIONS" | grep -qi "Black"; then ((OPTIONS_FOUND_COUNT++)); fi
fi

echo "Attribute: Found=$ATTR_FOUND ID=$ATTR_ID Input=$ATTR_INPUT Options=[$OPTIONS_LIST] Count=$OPTIONS_FOUND_COUNT"

# ==============================================================================
# 2. VERIFY CONFIGURABLE PRODUCT ('SHIRT-OXFORD-001')
# ==============================================================================
echo "Checking product 'SHIRT-OXFORD-001'..."
PROD_DATA=$(magento_query "SELECT entity_id, type_id, sku FROM catalog_product_entity WHERE LOWER(TRIM(sku))='shirt-oxford-001'" 2>/dev/null | tail -1)
PROD_ID=$(echo "$PROD_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
PROD_TYPE=$(echo "$PROD_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
PROD_SKU=$(echo "$PROD_DATA" | awk -F'\t' '{print $3}')

PROD_FOUND="false"
[ -n "$PROD_ID" ] && PROD_FOUND="true"

# Get Name, Price
PROD_NAME=""
PROD_PRICE=""
if [ -n "$PROD_ID" ]; then
    PROD_NAME=$(get_product_name "$PROD_ID" 2>/dev/null)
    PROD_PRICE=$(get_product_price "$PROD_ID" 2>/dev/null)
fi

# Get Category
PROD_CATEGORY=""
if [ -n "$PROD_ID" ]; then
    # Look for category "Clothing" assignment
    CLOTHING_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar 
        WHERE value = 'Clothing' 
        AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3) 
        LIMIT 1" 2>/dev/null | tail -1)
    
    if [ -n "$CLOTHING_CAT_ID" ]; then
        IS_IN_CAT=$(magento_query "SELECT COUNT(*) FROM catalog_category_product WHERE product_id=$PROD_ID AND category_id=$CLOTHING_CAT_ID" 2>/dev/null | tail -1)
        [ "$IS_IN_CAT" -gt "0" ] && PROD_CATEGORY="Clothing"
    fi
fi

echo "Product: Found=$PROD_FOUND Type=$PROD_TYPE Name='$PROD_NAME' Price=$PROD_PRICE Category='$PROD_CATEGORY'"

# ==============================================================================
# 3. VERIFY VARIANTS (Simple products linked to Configurable)
# ==============================================================================
VARIANT_COUNT=0
if [ -n "$PROD_ID" ]; then
    # Count simple products linked to this parent
    VARIANT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_link WHERE parent_id=$PROD_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
fi
echo "Variants linked: $VARIANT_COUNT"

# ==============================================================================
# 4. EXPORT JSON
# ==============================================================================

# Escape for JSON
PROD_NAME_ESC=$(echo "$PROD_NAME" | sed 's/"/\\"/g')
PROD_SKU_ESC=$(echo "$PROD_SKU" | sed 's/"/\\"/g')
OPTIONS_LIST_ESC=$(echo "$OPTIONS_LIST" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/config_prod_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_attr_count": ${INITIAL_ATTR_COUNT:-0},
    "initial_product_count": ${INITIAL_PRODUCT_COUNT:-0},
    "initial_link_count": ${INITIAL_LINK_COUNT:-0},
    
    "attribute_found": $ATTR_FOUND,
    "attribute_id": "${ATTR_ID:-}",
    "attribute_input": "${ATTR_INPUT:-}",
    "options_found_count": ${OPTIONS_FOUND_COUNT:-0},
    "options_list": "$OPTIONS_LIST_ESC",
    
    "product_found": $PROD_FOUND,
    "product_id": "${PROD_ID:-}",
    "product_type": "${PROD_TYPE:-}",
    "product_sku": "$PROD_SKU_ESC",
    "product_name": "$PROD_NAME_ESC",
    "product_price": "${PROD_PRICE:-}",
    "product_category": "${PROD_CATEGORY:-}",
    
    "variant_count": ${VARIANT_COUNT:-0},
    
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/config_prod_result.json

echo ""
cat /tmp/config_prod_result.json
echo ""
echo "=== Export Complete ==="