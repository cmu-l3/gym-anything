#!/bin/bash
# Export script for create_external_product task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_external_product task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get current product count
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")

# Find the product
# Strategy 1: Search by SKU (most reliable)
PRODUCT_DATA=$(get_product_by_sku "EXT-SONY-WH1000XM5")

# Strategy 2: Search by Name (fallback)
if [ -z "$PRODUCT_DATA" ]; then
    PRODUCT_DATA=$(get_product_by_name "Sony WH-1000XM5")
fi

PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_SKU=""
PRODUCT_NAME=""
PRODUCT_PRICE=""
PRODUCT_TYPE=""
PRODUCT_STATUS=""
PRODUCT_URL=""
BUTTON_TEXT=""
PRODUCT_CATEGORIES=""
PRODUCT_DATE=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | awk '{print $1}')
    
    # Get basic details
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID")
    PRODUCT_PRICE=$(get_product_price "$PRODUCT_ID")
    PRODUCT_TYPE=$(get_product_type "$PRODUCT_ID")
    PRODUCT_STATUS=$(get_product_status "$PRODUCT_ID")
    PRODUCT_CATEGORIES=$(get_product_categories "$PRODUCT_ID")
    
    # Get external product specific meta fields
    PRODUCT_URL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_product_url' LIMIT 1")
    BUTTON_TEXT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_button_text' LIMIT 1")
    PRODUCT_SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sku' LIMIT 1")
    
    # Get creation timestamp
    PRODUCT_DATE_STR=$(wc_query "SELECT post_date FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1")
    PRODUCT_DATE=$(date -d "$PRODUCT_DATE_STR" +%s 2>/dev/null || echo "0")
fi

# Escape strings for JSON
PRODUCT_NAME_ESC=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')
PRODUCT_URL_ESC=$(echo "$PRODUCT_URL" | sed 's/"/\\"/g')
BUTTON_TEXT_ESC=$(echo "$BUTTON_TEXT" | sed 's/"/\\"/g')
PRODUCT_CATEGORIES_ESC=$(echo "$PRODUCT_CATEGORIES" | sed 's/"/\\"/g')

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "sku": "$PRODUCT_SKU",
        "type": "$PRODUCT_TYPE",
        "status": "$PRODUCT_STATUS",
        "regular_price": "$PRODUCT_PRICE",
        "product_url": "$PRODUCT_URL_ESC",
        "button_text": "$BUTTON_TEXT_ESC",
        "categories": "$PRODUCT_CATEGORIES_ESC",
        "created_timestamp": "$PRODUCT_DATE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="