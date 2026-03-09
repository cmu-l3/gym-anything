#!/bin/bash
# Export script for Create Product task

echo "=== Exporting Create Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current product count
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")

echo "Product count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent products
echo ""
echo "=== DEBUG: Most recent products in database ==="
magento_query_headers "SELECT entity_id, sku, type_id FROM catalog_product_entity ORDER BY entity_id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target product using case-insensitive SKU matching
echo "Checking for product SKU 'OCT-001' (case-insensitive)..."
PRODUCT_DATA=$(get_product_by_sku "OCT-001" 2>/dev/null)

# No fallback logic - we only accept the exact expected SKU
if [ -z "$PRODUCT_DATA" ]; then
    echo "Product with SKU 'OCT-001' NOT found in database"
fi

# Parse product data
PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_SKU=""
PRODUCT_TYPE=""
PRODUCT_NAME=""
PRODUCT_PRICE=""
PRODUCT_CATEGORY=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    PRODUCT_SKU=$(echo "$PRODUCT_DATA" | cut -f2)
    PRODUCT_TYPE=$(echo "$PRODUCT_DATA" | cut -f3)

    # Get product name and price from EAV tables
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID" 2>/dev/null)
    PRODUCT_PRICE=$(get_product_price "$PRODUCT_ID" 2>/dev/null)

    # Get product stock quantity from cataloginventory_stock_item table
    PRODUCT_STOCK_QTY=$(magento_query "SELECT qty FROM cataloginventory_stock_item WHERE product_id = $PRODUCT_ID" 2>/dev/null)
    # Clean up stock qty (remove trailing .0000 if present)
    PRODUCT_STOCK_QTY=$(echo "$PRODUCT_STOCK_QTY" | sed 's/\.0*$//')

    # Get product category name
    PRODUCT_CATEGORY=$(magento_query "SELECT v.value FROM catalog_category_product cp
        JOIN catalog_category_entity_varchar v ON cp.category_id = v.entity_id
        WHERE cp.product_id = $PRODUCT_ID
        AND v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
        AND v.store_id = 0
        LIMIT 1" 2>/dev/null)

    echo "Product found: ID=$PRODUCT_ID, SKU='$PRODUCT_SKU', Type='$PRODUCT_TYPE', Name='$PRODUCT_NAME', Price='$PRODUCT_PRICE', Stock='$PRODUCT_STOCK_QTY', Category='$PRODUCT_CATEGORY'"
else
    echo "Product 'OCT-001' NOT found in database"
    PRODUCT_STOCK_QTY=""
fi

# Escape special characters for JSON
PRODUCT_NAME_ESC=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')
PRODUCT_SKU_ESC=$(echo "$PRODUCT_SKU" | sed 's/"/\\"/g')
PRODUCT_CATEGORY_ESC=$(echo "$PRODUCT_CATEGORY" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/create_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_product_count": ${INITIAL_COUNT:-0},
    "current_product_count": ${CURRENT_COUNT:-0},
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "sku": "$PRODUCT_SKU_ESC",
        "price": "$PRODUCT_PRICE",
        "stock_qty": "$PRODUCT_STOCK_QTY",
        "type": "$PRODUCT_TYPE",
        "category": "$PRODUCT_CATEGORY_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_product_result.json

echo ""
cat /tmp/create_product_result.json
echo ""
echo "=== Export Complete ==="
