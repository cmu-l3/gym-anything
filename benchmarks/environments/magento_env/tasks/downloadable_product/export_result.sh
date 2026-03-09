#!/bin/bash
# Export script for Downloadable Product task

echo "=== Exporting Downloadable Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get current product count
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")
echo "Product count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Check for the product by SKU
SKU="DWAC-VOL1"
echo "Checking for product SKU '$SKU'..."
PRODUCT_DATA=$(get_product_by_sku "$SKU" 2>/dev/null)

PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_TYPE=""
PRODUCT_NAME=""
PRODUCT_PRICE=""
LINKS_PURCHASED_SEPARATELY=""
LINKS_JSON="[]"

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    PRODUCT_SKU=$(echo "$PRODUCT_DATA" | cut -f2)
    PRODUCT_TYPE=$(echo "$PRODUCT_DATA" | cut -f3) # Should be 'downloadable'
    
    # Get Name
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID" 2>/dev/null)
    
    # Get Price
    PRODUCT_PRICE=$(get_product_price "$PRODUCT_ID" 2>/dev/null)
    
    # Get 'links_purchased_separately' attribute
    # Note: Attribute code might vary, but usually 'links_purchased_separately'
    LINKS_PURCHASED_SEPARATELY=$(magento_query "SELECT value FROM catalog_product_entity_int 
        WHERE entity_id=$PRODUCT_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='links_purchased_separately' AND entity_type_id=4) 
        AND store_id=0 LIMIT 1" 2>/dev/null)

    # Get Downloadable Links
    # We need to join downloadable_link, downloadable_link_title, downloadable_link_price
    echo "Querying downloadable links..."
    
    # Construct a JSON array of links manually via loop or complex query
    # Using a loop over IDs is safer with shell string manipulation
    LINK_IDS=$(magento_query "SELECT link_id FROM downloadable_link WHERE product_id=$PRODUCT_ID" 2>/dev/null)
    
    LINKS_ARRAY=()
    for LID in $LINK_IDS; do
        # Get Title
        LTITLE=$(magento_query "SELECT title FROM downloadable_link_title WHERE link_id=$LID AND store_id=0" 2>/dev/null)
        # Get Price (default to 0 if null)
        LPRICE=$(magento_query "SELECT price FROM downloadable_link_price WHERE link_id=$LID AND website_id=0" 2>/dev/null)
        [ -z "$LPRICE" ] && LPRICE="0.0000"
        # Get Max Downloads
        LDOWNLOADS=$(magento_query "SELECT number_of_downloads FROM downloadable_link WHERE link_id=$LID" 2>/dev/null)
        # Get Link Type
        LTYPE=$(magento_query "SELECT link_type FROM downloadable_link WHERE link_id=$LID" 2>/dev/null)
        
        # Escape title for JSON
        LTITLE_ESC=$(echo "$LTITLE" | sed 's/"/\\"/g')
        
        # Add to array object
        LINKS_ARRAY+=("{\"id\": $LID, \"title\": \"$LTITLE_ESC\", \"price\": \"$LPRICE\", \"downloads\": \"$LDOWNLOADS\", \"type\": \"$LTYPE\"}")
    done
    
    # Join array with commas
    LINKS_JSON="[$(IFS=,; echo "${LINKS_ARRAY[*]}")]"
    
    echo "Product found: ID=$PRODUCT_ID Type=$PRODUCT_TYPE Name='$PRODUCT_NAME'"
    echo "Links found: ${#LINKS_ARRAY[@]}"
else
    echo "Product '$SKU' NOT found"
fi

# Escape Product Name
PRODUCT_NAME_ESC=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/downloadable_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "sku": "$SKU",
        "type": "$PRODUCT_TYPE",
        "name": "$PRODUCT_NAME_ESC",
        "price": "$PRODUCT_PRICE",
        "links_purchased_separately": "$LINKS_PURCHASED_SEPARATELY",
        "links": $LINKS_JSON
    }
}
EOF

safe_write_json "$TEMP_JSON" /tmp/downloadable_result.json

echo ""
cat /tmp/downloadable_result.json
echo ""
echo "=== Export Complete ==="