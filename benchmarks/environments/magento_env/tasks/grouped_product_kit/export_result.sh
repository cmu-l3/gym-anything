#!/bin/bash
# Export script for Grouped Product Kit task

echo "=== Exporting Grouped Product Kit Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get counts
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")

echo "Product count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Target SKU
TARGET_SKU="HOMEGYM-KIT-001"

echo "Checking for product SKU '$TARGET_SKU'..."
# Get basic product data
PRODUCT_DATA=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null)

PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_SKU=""
PRODUCT_TYPE=""
PRODUCT_NAME=""
PRODUCT_STATUS=""
PRODUCT_VISIBILITY=""
PRODUCT_CATEGORY=""
LINKED_PRODUCTS_JSON="[]"

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    PRODUCT_SKU=$(echo "$PRODUCT_DATA" | cut -f2)
    PRODUCT_TYPE=$(echo "$PRODUCT_DATA" | cut -f3)

    # Get Name
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID" 2>/dev/null)

    # Get Status (attribute_code='status', entity_type_id=4)
    # 1=Enabled, 2=Disabled
    PRODUCT_STATUS=$(magento_query "SELECT value FROM catalog_product_entity_int v JOIN eav_attribute a ON v.attribute_id = a.attribute_id WHERE a.attribute_code = 'status' AND a.entity_type_id = 4 AND v.entity_id = $PRODUCT_ID AND v.store_id = 0 LIMIT 1" 2>/dev/null)

    # Get Visibility (attribute_code='visibility', entity_type_id=4)
    # 4=Catalog, Search
    PRODUCT_VISIBILITY=$(magento_query "SELECT value FROM catalog_product_entity_int v JOIN eav_attribute a ON v.attribute_id = a.attribute_id WHERE a.attribute_code = 'visibility' AND a.entity_type_id = 4 AND v.entity_id = $PRODUCT_ID AND v.store_id = 0 LIMIT 1" 2>/dev/null)

    # Get Category Name
    # Join catalog_category_product -> catalog_category_entity_varchar (name)
    PRODUCT_CATEGORY=$(magento_query "SELECT v.value FROM catalog_category_product cp JOIN catalog_category_entity_varchar v ON cp.category_id = v.entity_id WHERE cp.product_id = $PRODUCT_ID AND v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3) AND v.store_id = 0 LIMIT 1" 2>/dev/null)

    # Get Linked Products (Grouped products use link_type_id = 3 for 'super'/'associated')
    # We want SKU and Quantity (qty is in catalog_product_link_attribute_decimal)
    # This query constructs a simple JSON-like string of linked SKUs
    # Note: Quantity for grouped product links is stored in catalog_product_link_attribute_decimal where attribute_code='qty' (usually attribute_id is distinct per link type, but often mapped)
    # For simplicity, we just check existence of links to specific SKUs first.

    LINKED_SKUS_RAW=$(magento_query "SELECT cpe.sku FROM catalog_product_link cpl JOIN catalog_product_entity cpe ON cpl.linked_product_id = cpe.entity_id WHERE cpl.product_id = $PRODUCT_ID AND cpl.link_type_id = 3" 2>/dev/null)
    
    # Convert newline separated SKUs to JSON array
    LINKED_PRODUCTS_JSON=$(echo "$LINKED_SKUS_RAW" | jq -R -s -c 'split("\n")[:-1]')

    echo "Product found: ID=$PRODUCT_ID, Type=$PRODUCT_TYPE, Name='$PRODUCT_NAME', Status=$PRODUCT_STATUS, Category='$PRODUCT_CATEGORY'"
    echo "Linked SKUs: $LINKED_PRODUCTS_JSON"
else
    echo "Product '$TARGET_SKU' NOT found in database"
fi

# Escape for JSON
PRODUCT_NAME_ESC=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')
PRODUCT_CATEGORY_ESC=$(echo "$PRODUCT_CATEGORY" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/grouped_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_product_count": ${INITIAL_COUNT:-0},
    "current_product_count": ${CURRENT_COUNT:-0},
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "sku": "${PRODUCT_SKU}",
        "type": "${PRODUCT_TYPE}",
        "name": "${PRODUCT_NAME_ESC}",
        "status": "${PRODUCT_STATUS}",
        "visibility": "${PRODUCT_VISIBILITY}",
        "category": "${PRODUCT_CATEGORY_ESC}",
        "linked_skus": $LINKED_PRODUCTS_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/grouped_product_result.json

echo ""
cat /tmp/grouped_product_result.json
echo ""
echo "=== Export Complete ==="