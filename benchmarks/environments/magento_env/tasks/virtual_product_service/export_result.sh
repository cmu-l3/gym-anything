#!/bin/bash
# Export script for Virtual Product Service task

echo "=== Exporting Virtual Product Service Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_MAX_ID=$(cat /tmp/initial_max_product_id 2>/dev/null || echo "0")
EXPECTED_SKU="SVC-HT-INSTALL"

# 1. Check if product exists and get basic info
echo "Checking for SKU '$EXPECTED_SKU'..."
PRODUCT_DATA=$(magento_query "SELECT entity_id, type_id, sku, created_at FROM catalog_product_entity WHERE sku='$EXPECTED_SKU' LIMIT 1" 2>/dev/null | tail -1)

PRODUCT_FOUND="false"
ENTITY_ID=""
TYPE_ID=""
REAL_SKU=""
CREATED_AT=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    ENTITY_ID=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    TYPE_ID=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    REAL_SKU=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    CREATED_AT=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $4}')
fi

echo "Product Found: $PRODUCT_FOUND (ID: $ENTITY_ID, Type: $TYPE_ID)"

# 2. Get Product Name (Attribute Code 'name')
PRODUCT_NAME=""
if [ -n "$ENTITY_ID" ]; then
    PRODUCT_NAME=$(magento_query "SELECT value FROM catalog_product_entity_varchar 
        WHERE entity_id=$ENTITY_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=4) 
        AND store_id=0 LIMIT 1" 2>/dev/null | tail -1)
fi

# 3. Get Price (Attribute Code 'price')
PRODUCT_PRICE=""
if [ -n "$ENTITY_ID" ]; then
    PRODUCT_PRICE=$(magento_query "SELECT value FROM catalog_product_entity_decimal 
        WHERE entity_id=$ENTITY_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='price' AND entity_type_id=4) 
        AND store_id=0 LIMIT 1" 2>/dev/null | tail -1)
    # Remove trailing zeros
    PRODUCT_PRICE=$(echo "$PRODUCT_PRICE" | sed 's/\.0000$//' | sed 's/\.00$//')
fi

# 4. Get Visibility (Attribute Code 'visibility')
# 1=Not Visible, 2=Catalog, 3=Search, 4=Catalog, Search
PRODUCT_VISIBILITY=""
if [ -n "$ENTITY_ID" ]; then
    PRODUCT_VISIBILITY=$(magento_query "SELECT value FROM catalog_product_entity_int 
        WHERE entity_id=$ENTITY_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='visibility' AND entity_type_id=4) 
        AND store_id=0 LIMIT 1" 2>/dev/null | tail -1)
fi

# 5. Get Category Assignment
# Check if assigned to 'Electronics' category
IS_IN_ELECTRONICS="false"
if [ -n "$ENTITY_ID" ]; then
    # Find category ID for 'Electronics'
    ELEC_CAT_ID=$(magento_query "SELECT e.entity_id FROM catalog_category_entity e 
        JOIN catalog_category_entity_varchar v ON e.entity_id=v.entity_id 
        WHERE v.value='Electronics' AND v.attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3) 
        LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    
    if [ -n "$ELEC_CAT_ID" ]; then
        ASSIGNMENT_CHECK=$(magento_query "SELECT COUNT(*) FROM catalog_category_product WHERE product_id=$ENTITY_ID AND category_id=$ELEC_CAT_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        if [ "$ASSIGNMENT_CHECK" -gt "0" ]; then
            IS_IN_ELECTRONICS="true"
        fi
    fi
fi

# 6. Check Quantity
PRODUCT_QTY="0"
if [ -n "$ENTITY_ID" ]; then
    PRODUCT_QTY=$(magento_query "SELECT qty FROM cataloginventory_stock_item WHERE product_id=$ENTITY_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    PRODUCT_QTY=$(echo "$PRODUCT_QTY" | sed 's/\.0000$//')
fi

# Check if newly created
IS_NEWLY_CREATED="false"
if [ -n "$ENTITY_ID" ] && [ "$ENTITY_ID" -gt "$INITIAL_MAX_ID" ]; then
    IS_NEWLY_CREATED="true"
fi

# Escape strings for JSON
PRODUCT_NAME_ESC=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/virtual_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "entity_id": "${ENTITY_ID:-0}",
    "type_id": "${TYPE_ID:-}",
    "sku": "${REAL_SKU:-}",
    "name": "$PRODUCT_NAME_ESC",
    "price": "${PRODUCT_PRICE:-0}",
    "qty": "${PRODUCT_QTY:-0}",
    "visibility": "${PRODUCT_VISIBILITY:-0}",
    "is_in_electronics_category": $IS_IN_ELECTRONICS,
    "initial_max_id": ${INITIAL_MAX_ID:-0},
    "is_newly_created": $IS_NEWLY_CREATED,
    "created_at": "${CREATED_AT:-}"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/virtual_product_result.json

echo "Result stored in /tmp/virtual_product_result.json"
cat /tmp/virtual_product_result.json
echo "=== Export Complete ==="