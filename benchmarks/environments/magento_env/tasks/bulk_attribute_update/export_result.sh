#!/bin/bash
# Export script for Bulk Attribute Update task

echo "=== Exporting Bulk Attribute Update Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Parameters
TARGET_CATEGORY="Clothing"
CONTROL_CATEGORY="Electronics"

# 1. Get Attribute IDs
COST_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='cost' AND entity_type_id=4" 2>/dev/null | tail -1)
META_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='meta_keyword' AND entity_type_id=4" 2>/dev/null | tail -1)

# 2. Get Target Products (Clothing)
CLOTHING_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar WHERE value = '$TARGET_CATEGORY' AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'name') LIMIT 1" 2>/dev/null | tail -1)
TARGET_PIDS=$(magento_query "SELECT product_id FROM catalog_category_product WHERE category_id = $CLOTHING_CAT_ID" 2>/dev/null)
# Convert newlines to spaces for iteration
TARGET_PIDS_LIST=$(echo "$TARGET_PIDS" | tr '\n' ' ')

echo "Target Product IDs: $TARGET_PIDS_LIST"

# 3. Collect Data for Target Products
TARGET_DATA="[]"
if [ -n "$TARGET_PIDS_LIST" ]; then
    # Construct JSON array of objects
    TARGET_DATA_ITEMS=""
    for PID in $TARGET_PIDS_LIST; do
        SKU=$(magento_query "SELECT sku FROM catalog_product_entity WHERE entity_id=$PID" 2>/dev/null | tail -1)
        
        # Get Cost
        COST=$(magento_query "SELECT value FROM catalog_product_entity_decimal WHERE entity_id=$PID AND attribute_id=$COST_ATTR_ID AND store_id=0" 2>/dev/null | tail -1)
        
        # Get Meta Keywords
        META=$(magento_query "SELECT value FROM catalog_product_entity_text WHERE entity_id=$PID AND attribute_id=$META_ATTR_ID AND store_id=0" 2>/dev/null | tail -1)
        
        # Get Updated At
        UPDATED_AT=$(magento_query "SELECT updated_at FROM catalog_product_entity WHERE entity_id=$PID" 2>/dev/null | tail -1)
        
        # Escape strings
        SKU_ESC=$(echo "$SKU" | sed 's/"/\\"/g')
        META_ESC=$(echo "$META" | sed 's/"/\\"/g')
        
        ITEM="{\"id\": $PID, \"sku\": \"$SKU_ESC\", \"cost\": \"$COST\", \"meta_keyword\": \"$META_ESC\", \"updated_at\": \"$UPDATED_AT\"}"
        
        if [ -z "$TARGET_DATA_ITEMS" ]; then
            TARGET_DATA_ITEMS="$ITEM"
        else
            TARGET_DATA_ITEMS="$TARGET_DATA_ITEMS, $ITEM"
        fi
    done
    TARGET_DATA="[$TARGET_DATA_ITEMS]"
fi

# 4. Collect Data for Control Product (Anti-Gaming / Precision)
CONTROL_PID=$(cat /tmp/control_pid.txt 2>/dev/null | tr -d '[:space:]')
CONTROL_DATA="{}"
if [ -n "$CONTROL_PID" ]; then
    SKU=$(magento_query "SELECT sku FROM catalog_product_entity WHERE entity_id=$CONTROL_PID" 2>/dev/null | tail -1)
    COST=$(magento_query "SELECT value FROM catalog_product_entity_decimal WHERE entity_id=$CONTROL_PID AND attribute_id=$COST_ATTR_ID AND store_id=0" 2>/dev/null | tail -1)
    META=$(magento_query "SELECT value FROM catalog_product_entity_text WHERE entity_id=$CONTROL_PID AND attribute_id=$META_ATTR_ID AND store_id=0" 2>/dev/null | tail -1)
    
    SKU_ESC=$(echo "$SKU" | sed 's/"/\\"/g')
    META_ESC=$(echo "$META" | sed 's/"/\\"/g')
    CONTROL_DATA="{\"id\": $CONTROL_PID, \"sku\": \"$SKU_ESC\", \"cost\": \"$COST\", \"meta_keyword\": \"$META_ESC\"}"
fi

# 5. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/bulk_update_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "current_time": $CURRENT_TIME,
    "target_category": "$TARGET_CATEGORY",
    "target_products": $TARGET_DATA,
    "control_product": $CONTROL_DATA,
    "initial_timestamps_file_exists": $([ -f /tmp/initial_timestamps.txt ] && echo "true" || echo "false")
}
EOF

safe_write_json "$TEMP_JSON" /tmp/bulk_update_result.json

echo ""
cat /tmp/bulk_update_result.json
echo ""
echo "=== Export Complete ==="