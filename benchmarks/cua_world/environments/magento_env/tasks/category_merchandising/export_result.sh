#!/bin/bash
# Export script for Category Merchandising task

echo "=== Exporting Category Merchandising Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Category ID for 'Electronics'
echo "Looking for Electronics category..."
CAT_DATA=$(get_category_by_name "Electronics")
CAT_ID=$(echo "$CAT_DATA" | cut -f1)

CAT_FOUND="false"
SORT_BY_VALUE=""
LAPTOP_POS="-1"
PHONE_POS="-1"
HEADPHONES_POS="-1"

if [ -n "$CAT_ID" ]; then
    CAT_FOUND="true"
    echo "Found Electronics Category ID: $CAT_ID"

    # 1. Get current Sort By setting
    # attribute_code = 'default_sort_by', entity_type_id = 3 (category)
    SORT_BY_VALUE=$(magento_query "SELECT value FROM catalog_category_entity_varchar 
        WHERE entity_id = $CAT_ID 
        AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='default_sort_by' AND entity_type_id=3) 
        AND store_id = 0 LIMIT 1")
    
    echo "Current Sort By: '$SORT_BY_VALUE'"

    # 2. Get Product Positions
    # Helper to get position for a SKU
    get_position_for_sku() {
        local sku="$1"
        local pid_data=$(get_product_by_sku "$sku")
        local pid=$(echo "$pid_data" | cut -f1)
        
        if [ -n "$pid" ]; then
            local pos=$(magento_query "SELECT position FROM catalog_category_product WHERE category_id = $CAT_ID AND product_id = $pid LIMIT 1")
            echo "${pos:-0}"
        else
            echo "-1"
        fi
    }

    LAPTOP_POS=$(get_position_for_sku "LAPTOP-001")
    PHONE_POS=$(get_position_for_sku "PHONE-001")
    HEADPHONES_POS=$(get_position_for_sku "HEADPHONES-001")

    echo "Positions found: Laptop=$LAPTOP_POS, Phone=$PHONE_POS, Headphones=$HEADPHONES_POS"
else
    echo "ERROR: Electronics category not found"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/merchandising_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "category_found": $CAT_FOUND,
    "category_id": "${CAT_ID:-}",
    "sort_by_setting": "${SORT_BY_VALUE:-}",
    "positions": {
        "laptop": $LAPTOP_POS,
        "phone": $PHONE_POS,
        "headphones": $HEADPHONES_POS
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/merchandising_result.json

echo ""
cat /tmp/merchandising_result.json
echo ""
echo "=== Export Complete ==="