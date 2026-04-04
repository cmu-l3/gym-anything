#!/bin/bash
# Export script for Create Configurable Product task

echo "=== Exporting Configure Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read initial counts
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")
INITIAL_CONFIGURABLE_COUNT=$(cat /tmp/initial_configurable_count 2>/dev/null || echo "0")
COLOR_ATTR_ID=$(cat /tmp/color_attribute_id 2>/dev/null | tr -d '[:space:]' || echo "0")

# Current configurable count
CURRENT_CONFIGURABLE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity WHERE type_id='configurable'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Find parent configurable product by SKU
PARENT_DATA=$(magento_query "SELECT entity_id, sku, type_id FROM catalog_product_entity WHERE LOWER(TRIM(sku))='tms-bp-45l' LIMIT 1" 2>/dev/null | tail -1)
PARENT_ENTITY_ID=$(echo "$PARENT_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
PARENT_SKU=$(echo "$PARENT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
PARENT_TYPE=$(echo "$PARENT_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

PARENT_FOUND="false"
PARENT_IS_CONFIGURABLE="false"
[ -n "$PARENT_ENTITY_ID" ] && PARENT_FOUND="true"
[ "$PARENT_TYPE" = "configurable" ] && PARENT_IS_CONFIGURABLE="true"
echo "Parent product: ID=$PARENT_ENTITY_ID SKU=$PARENT_SKU Type=$PARENT_TYPE"

# Find Black child product
BLACK_DATA=$(magento_query "SELECT entity_id, sku, type_id FROM catalog_product_entity WHERE LOWER(TRIM(sku))='tms-bp-45l-blk' LIMIT 1" 2>/dev/null | tail -1)
BLACK_ENTITY_ID=$(echo "$BLACK_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
BLACK_FOUND="false"
[ -n "$BLACK_ENTITY_ID" ] && BLACK_FOUND="true"

# Find Green child product
GREEN_DATA=$(magento_query "SELECT entity_id, sku, type_id FROM catalog_product_entity WHERE LOWER(TRIM(sku))='tms-bp-45l-grn' LIMIT 1" 2>/dev/null | tail -1)
GREEN_ENTITY_ID=$(echo "$GREEN_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
GREEN_FOUND="false"
[ -n "$GREEN_ENTITY_ID" ] && GREEN_FOUND="true"
echo "Black child: ID=$BLACK_ENTITY_ID found=$BLACK_FOUND | Green child: ID=$GREEN_ENTITY_ID found=$GREEN_FOUND"

# Check parent-child relationships
CHILD_COUNT="0"
if [ -n "$PARENT_ENTITY_ID" ]; then
    CHILD_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_relation WHERE parent_id=$PARENT_ENTITY_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
fi

# Check super attribute (any configurable attribute on parent)
SUPER_ATTR_ANY="0"
SUPER_ATTR_COLOR="0"
if [ -n "$PARENT_ENTITY_ID" ]; then
    SUPER_ATTR_ANY=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_attribute WHERE product_id=$PARENT_ENTITY_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    if [ "$COLOR_ATTR_ID" != "0" ] && [ -n "$COLOR_ATTR_ID" ]; then
        SUPER_ATTR_COLOR=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_attribute WHERE product_id=$PARENT_ENTITY_ID AND attribute_id=$COLOR_ATTR_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    fi
fi
echo "Super attributes: any=$SUPER_ATTR_ANY color=$SUPER_ATTR_COLOR"

# Check category assignment (Sports)
CATEGORY_ASSIGNED="false"
if [ -n "$PARENT_ENTITY_ID" ]; then
    CAT_CHECK=$(magento_query "SELECT COUNT(*) FROM catalog_category_product ccp JOIN catalog_category_entity_varchar ccev ON ccp.category_id=ccev.entity_id WHERE ccp.product_id=$PARENT_ENTITY_ID AND LOWER(TRIM(ccev.value)) LIKE '%sport%' AND ccev.store_id=0" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    [ "${CAT_CHECK:-0}" -gt "0" ] 2>/dev/null && CATEGORY_ASSIGNED="true"
fi

# Get parent product price
PARENT_PRICE=""
if [ -n "$PARENT_ENTITY_ID" ]; then
    PARENT_PRICE=$(magento_query "SELECT ROUND(value,2) FROM catalog_product_entity_decimal WHERE entity_id=$PARENT_ENTITY_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='price' AND entity_type_id=(SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code='catalog_product')) AND store_id=0 LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "")
fi

# Get green child price (to verify variant-specific pricing)
GREEN_PRICE=""
if [ -n "$GREEN_ENTITY_ID" ]; then
    GREEN_PRICE=$(magento_query "SELECT ROUND(value,2) FROM catalog_product_entity_decimal WHERE entity_id=$GREEN_ENTITY_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='price' AND entity_type_id=(SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code='catalog_product')) AND store_id=0 LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "")
fi

# Get stock quantities for children
BLACK_QTY="0"
GREEN_QTY="0"
if [ -n "$BLACK_ENTITY_ID" ]; then
    BLACK_QTY=$(magento_query "SELECT COALESCE(MAX(qty),0) FROM cataloginventory_stock_item WHERE product_id=$BLACK_ENTITY_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' | sed 's/\..*$//' || echo "0")
    # Fallback: try MSI inventory table
    if [ "${BLACK_QTY:-0}" = "0" ]; then
        BLACK_QTY=$(magento_query "SELECT COALESCE(MAX(quantity),0) FROM inventory_source_item WHERE LOWER(sku)='tms-bp-45l-blk'" 2>/dev/null | tail -1 | tr -d '[:space:]' | sed 's/\..*$//' || echo "0")
    fi
fi
if [ -n "$GREEN_ENTITY_ID" ]; then
    GREEN_QTY=$(magento_query "SELECT COALESCE(MAX(qty),0) FROM cataloginventory_stock_item WHERE product_id=$GREEN_ENTITY_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' | sed 's/\..*$//' || echo "0")
    if [ "${GREEN_QTY:-0}" = "0" ]; then
        GREEN_QTY=$(magento_query "SELECT COALESCE(MAX(quantity),0) FROM inventory_source_item WHERE LOWER(sku)='tms-bp-45l-grn'" 2>/dev/null | tail -1 | tr -d '[:space:]' | sed 's/\..*$//' || echo "0")
    fi
fi
echo "Stock: Black=$BLACK_QTY Green=$GREEN_QTY"

# Escape values for JSON
PARENT_SKU_ESC=$(echo "$PARENT_SKU" | sed 's/"/\\"/g')
PARENT_PRICE_ESC=$(echo "$PARENT_PRICE" | sed 's/"/\\"/g')
GREEN_PRICE_ESC=$(echo "$GREEN_PRICE" | sed 's/"/\\"/g')

# Write result JSON
TEMP_JSON=$(mktemp /tmp/configure_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_product_count": ${INITIAL_PRODUCT_COUNT:-0},
    "initial_configurable_count": ${INITIAL_CONFIGURABLE_COUNT:-0},
    "current_configurable_count": ${CURRENT_CONFIGURABLE_COUNT:-0},
    "parent_found": $PARENT_FOUND,
    "parent_is_configurable": $PARENT_IS_CONFIGURABLE,
    "parent_sku": "$PARENT_SKU_ESC",
    "parent_entity_id": "${PARENT_ENTITY_ID:-}",
    "parent_price": "${PARENT_PRICE_ESC:-}",
    "black_child_found": $BLACK_FOUND,
    "green_child_found": $GREEN_FOUND,
    "black_entity_id": "${BLACK_ENTITY_ID:-}",
    "green_entity_id": "${GREEN_ENTITY_ID:-}",
    "child_count_in_relation": ${CHILD_COUNT:-0},
    "super_attr_any_count": ${SUPER_ATTR_ANY:-0},
    "super_attr_color_count": ${SUPER_ATTR_COLOR:-0},
    "category_assigned_sports": $CATEGORY_ASSIGNED,
    "green_child_price": "${GREEN_PRICE_ESC:-}",
    "black_child_qty": ${BLACK_QTY:-0},
    "green_child_qty": ${GREEN_QTY:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_product_result.json

echo ""
cat /tmp/configure_product_result.json
echo ""
echo "=== Export Complete ==="
