#!/bin/bash
# Export script for MAP Pricing Config task

echo "=== Exporting MAP Pricing Config Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Global Configuration
echo "Checking global MAP settings..."
GLOBAL_MAP_ENABLED=$(magento_query "SELECT value FROM core_config_data WHERE path = 'sales/msrp/enabled'" 2>/dev/null)
GLOBAL_MAP_MESSAGE=$(magento_query "SELECT value FROM core_config_data WHERE path = 'sales/msrp/explanation_message'" 2>/dev/null)

echo "Global Enabled: $GLOBAL_MAP_ENABLED"
echo "Global Message: $GLOBAL_MAP_MESSAGE"

# 2. Check Product Configuration for LAPTOP-001
echo "Checking product settings for LAPTOP-001..."
PRODUCT_ID=$(get_product_by_sku "LAPTOP-001" 2>/dev/null | cut -f1)

PRODUCT_FOUND="false"
PRODUCT_MSRP=""
PRODUCT_DISPLAY_TYPE=""

if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
    
    # Get Attribute IDs and Backend Types
    MSRP_INFO=$(magento_query "SELECT attribute_id, backend_type FROM eav_attribute WHERE attribute_code='msrp' AND entity_type_id=4" 2>/dev/null)
    DISPLAY_INFO=$(magento_query "SELECT attribute_id, backend_type FROM eav_attribute WHERE attribute_code='msrp_display_actual_price_type' AND entity_type_id=4" 2>/dev/null)
    
    MSRP_ID=$(echo "$MSRP_INFO" | cut -f1)
    MSRP_TYPE=$(echo "$MSRP_INFO" | cut -f2) # usually decimal
    
    DISPLAY_ID=$(echo "$DISPLAY_INFO" | cut -f1)
    DISPLAY_TYPE=$(echo "$DISPLAY_INFO" | cut -f2) # usually varchar or int

    # Query MSRP
    if [ -n "$MSRP_ID" ]; then
        TABLE="catalog_product_entity_${MSRP_TYPE}"
        PRODUCT_MSRP=$(magento_query "SELECT value FROM $TABLE WHERE entity_id=$PRODUCT_ID AND attribute_id=$MSRP_ID AND store_id=0" 2>/dev/null)
    fi

    # Query Display Type
    if [ -n "$DISPLAY_ID" ]; then
        TABLE="catalog_product_entity_${DISPLAY_TYPE}"
        PRODUCT_DISPLAY_TYPE=$(magento_query "SELECT value FROM $TABLE WHERE entity_id=$PRODUCT_ID AND attribute_id=$DISPLAY_ID AND store_id=0" 2>/dev/null)
        
        # Fallback check: sometimes backend_type says varchar but it's in int, or vice versa if schema changed
        if [ -z "$PRODUCT_DISPLAY_TYPE" ]; then
             PRODUCT_DISPLAY_TYPE=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=$DISPLAY_ID AND store_id=0" 2>/dev/null)
        fi
        if [ -z "$PRODUCT_DISPLAY_TYPE" ]; then
             PRODUCT_DISPLAY_TYPE=$(magento_query "SELECT value FROM catalog_product_entity_int WHERE entity_id=$PRODUCT_ID AND attribute_id=$DISPLAY_ID AND store_id=0" 2>/dev/null)
        fi
    fi
fi

echo "Product Found: $PRODUCT_FOUND"
echo "Product MSRP: $PRODUCT_MSRP"
echo "Product Display Type: $PRODUCT_DISPLAY_TYPE"

# Clean up MSRP (remove trailing zeros)
if [ -n "$PRODUCT_MSRP" ]; then
    PRODUCT_MSRP=$(echo "$PRODUCT_MSRP" | sed 's/0*$//' | sed 's/\.$//')
fi

# Escape JSON strings
GLOBAL_MAP_MESSAGE_ESC=$(echo "$GLOBAL_MAP_MESSAGE" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/map_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "global_map_enabled": "${GLOBAL_MAP_ENABLED:-0}",
    "global_map_message": "$GLOBAL_MAP_MESSAGE_ESC",
    "product_found": $PRODUCT_FOUND,
    "product_id": "${PRODUCT_ID:-}",
    "product_msrp": "${PRODUCT_MSRP:-}",
    "product_display_type": "${PRODUCT_DISPLAY_TYPE:-}"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/map_task_result.json

echo ""
cat /tmp/map_task_result.json
echo ""
echo "=== Export Complete ==="