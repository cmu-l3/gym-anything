#!/bin/bash
# Export script for Bulk Product Import task

echo "=== Exporting Bulk Product Import Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_kitchen_count 2>/dev/null || echo "0")

# Define expected SKUs
SKUS=(
  "KITCHEN-CF01" "KITCHEN-KN01" "KITCHEN-CB01" "KITCHEN-MP01" 
  "KITCHEN-BL01" "KITCHEN-TK01" "KITCHEN-MS01" "KITCHEN-SP01" 
  "KITCHEN-CS01" "KITCHEN-RC01" "KITCHEN-TP01" "KITCHEN-WK01"
)

# Initialize JSON array
JSON_PRODUCTS="["
FIRST=1

for sku in "${SKUS[@]}"; do
    if [ "$FIRST" -eq 0 ]; then JSON_PRODUCTS+=","; fi
    FIRST=0
    
    echo "Checking SKU: $sku"
    
    # Get product ID and base info
    PROD_DATA=$(magento_query "SELECT entity_id, sku, created_at FROM catalog_product_entity WHERE sku='$sku' LIMIT 1" 2>/dev/null | tail -1)
    
    PID=$(echo "$PROD_DATA" | awk -F'\t' '{print $1}')
    PSKU=$(echo "$PROD_DATA" | awk -F'\t' '{print $2}')
    PCREATED=$(echo "$PROD_DATA" | awk -F'\t' '{print $3}')
    
    FOUND="false"
    PRICE="0"
    QTY="0"
    STATUS="0"
    VISIBILITY="0"
    
    if [ -n "$PID" ]; then
        FOUND="true"
        
        # Get Price
        PRICE=$(get_product_price "$PID" 2>/dev/null | sed 's/\.0000$//')
        if [ -z "$PRICE" ]; then PRICE="0"; fi
        
        # Get Qty
        QTY=$(magento_query "SELECT qty FROM cataloginventory_stock_item WHERE product_id=$PID" 2>/dev/null | tail -1 | sed 's/\.0000$//')
        if [ -z "$QTY" ]; then QTY="0"; fi
        
        # Get Status (1=Enabled)
        STATUS=$(magento_query "SELECT value FROM catalog_product_entity_int WHERE entity_id=$PID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='status' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)
        if [ -z "$STATUS" ]; then STATUS="0"; fi
        
        # Get Visibility (4=Catalog, Search)
        VISIBILITY=$(magento_query "SELECT value FROM catalog_product_entity_int WHERE entity_id=$PID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='visibility' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)
        if [ -z "$VISIBILITY" ]; then VISIBILITY="0"; fi
    fi
    
    # Append to JSON
    JSON_PRODUCTS+="{\"sku\": \"$sku\", \"found\": $FOUND, \"price\": \"$PRICE\", \"qty\": \"$QTY\", \"status\": \"$STATUS\", \"visibility\": \"$VISIBILITY\", \"created_at\": \"$PCREATED\"}"
done

JSON_PRODUCTS+="]"

# Count total kitchen products now
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity WHERE sku LIKE 'KITCHEN-%'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Write full result
TEMP_JSON=$(mktemp /tmp/import_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_kitchen_count": ${INITIAL_COUNT:-0},
    "current_kitchen_count": ${CURRENT_COUNT:-0},
    "products": $JSON_PRODUCTS
}
EOF

safe_write_json "$TEMP_JSON" /tmp/import_result.json

echo "Result export complete. Found $CURRENT_COUNT kitchen products."