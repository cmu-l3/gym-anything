#!/bin/bash
# Export script for Bulk Product Discontinuation task

echo "=== Exporting Result ==="
source /workspace/scripts/task_utils.sh

# Record timestamp
EXPORT_TIME=$(date +%s)
echo "$EXPORT_TIME" > /tmp/export_time.txt

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query Logic
# We need to check the status and tax_class_id for all LEG-* and CORE-* products
# Status Attribute ID: usually 97, but we should look it up
# Tax Class Attribute ID: usually 122, but we should look it up

echo "Looking up attribute IDs..."
STATUS_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='status' AND entity_type_id=4" | tail -1)
TAX_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='tax_class_id' AND entity_type_id=4" | tail -1)

echo "Attribute IDs: Status=$STATUS_ATTR_ID, Tax=$TAX_ATTR_ID"

# Helper function to get product data as JSON line
# Returns: {sku: "SKU", status: "1", tax_class: "2"}
get_product_data() {
    local prefix="$1"
    
    # Complex query to pivot the EAV data
    # We join catalog_product_entity with _int table twice (once for status, once for tax)
    # Note: store_id=0 is global scope
    
    magento_query "
    SELECT 
        e.sku,
        s.value as status,
        t.value as tax_class
    FROM catalog_product_entity e
    LEFT JOIN catalog_product_entity_int s 
        ON e.entity_id = s.entity_id 
        AND s.attribute_id = $STATUS_ATTR_ID 
        AND s.store_id = 0
    LEFT JOIN catalog_product_entity_int t 
        ON e.entity_id = t.entity_id 
        AND t.attribute_id = $TAX_ATTR_ID 
        AND t.store_id = 0
    WHERE e.sku LIKE '${prefix}%'
    ORDER BY e.sku
    " | while read -r line; do
        # Convert tab-separated to proper vars
        sku=$(echo "$line" | awk -F'\t' '{print $1}')
        status=$(echo "$line" | awk -F'\t' '{print $2}')
        tax=$(echo "$line" | awk -F'\t' '{print $3}')
        
        # Output minimal JSON object
        echo "{\"sku\": \"$sku\", \"status\": \"$status\", \"tax_class\": \"$tax\"},"
    done
}

# Generate JSON Data
echo "Querying Legacy products..."
LEGACY_JSON=$(get_product_data "LEG-")
# Remove trailing comma
LEGACY_JSON="[${LEGACY_JSON%,}]"

echo "Querying Core products..."
CORE_JSON=$(get_product_data "CORE-")
CORE_JSON="[${CORE_JSON%,}]"

# Create final result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": $EXPORT_TIME,
    "legacy_products": $LEGACY_JSON,
    "core_products": $CORE_JSON
}
EOF

safe_write_json "$TEMP_JSON" /tmp/bulk_update_result.json

echo "Data exported to /tmp/bulk_update_result.json"
cat /tmp/bulk_update_result.json
echo ""
echo "=== Export Complete ==="