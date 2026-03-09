#!/bin/bash
# Export script for Create Refurbished Product task

echo "=== Exporting Create Refurbished Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration
SOURCE_SKU="WBH-001"
TARGET_SKU="WBH-001-REF"
TARGET_NAME="Refurbished Wireless Bluetooth Headphones"

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Target Product Exists (by SKU preferably)
PRODUCT_DATA=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null)

# Fallback: Check by Name if SKU not found
if [ -z "$PRODUCT_DATA" ]; then
    echo "SKU match not found, checking by name..."
    PRODUCT_DATA=$(get_product_by_name "$TARGET_NAME" 2>/dev/null)
fi

PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_SKU=""
PRODUCT_NAME=""
PRODUCT_PRICE=""
PRODUCT_STOCK=""
PRODUCT_STATUS=""
PRODUCT_CONTENT_LENGTH="0"
SOURCE_CONTENT_LENGTH="0"
CREATED_AT="0"

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    PRODUCT_SKU=$(echo "$PRODUCT_DATA" | cut -f2)
    
    # Fetch details
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID")
    PRODUCT_PRICE=$(get_product_price "$PRODUCT_ID")
    PRODUCT_STOCK=$(get_product_stock "$PRODUCT_ID")
    PRODUCT_STATUS=$(get_product_status "$PRODUCT_ID")
    
    # Fetch content length (to verify description inheritance)
    PRODUCT_CONTENT=$(wc_query "SELECT post_content FROM wp_posts WHERE ID=$PRODUCT_ID")
    PRODUCT_CONTENT_LENGTH=${#PRODUCT_CONTENT}
    
    # Fetch creation time (Unix timestamp)
    CREATED_AT=$(wc_query "SELECT UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE ID=$PRODUCT_ID")
fi

# 2. Get Source Product Content Length for comparison
SOURCE_DATA=$(get_product_by_sku "$SOURCE_SKU" 2>/dev/null)
if [ -n "$SOURCE_DATA" ]; then
    SOURCE_ID=$(echo "$SOURCE_DATA" | cut -f1)
    SOURCE_CONTENT=$(wc_query "SELECT post_content FROM wp_posts WHERE ID=$SOURCE_ID")
    SOURCE_CONTENT_LENGTH=${#SOURCE_CONTENT}
fi

# Escape strings for JSON
PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")
PRODUCT_SKU_ESC=$(json_escape "$PRODUCT_SKU")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "sku": "$PRODUCT_SKU_ESC",
        "price": "$PRODUCT_PRICE",
        "stock": "$PRODUCT_STOCK",
        "status": "$PRODUCT_STATUS",
        "content_length": $PRODUCT_CONTENT_LENGTH,
        "created_at": "$CREATED_AT"
    },
    "source": {
        "content_length": $SOURCE_CONTENT_LENGTH
    },
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json