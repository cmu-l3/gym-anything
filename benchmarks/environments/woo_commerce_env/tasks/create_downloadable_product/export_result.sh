#!/bin/bash
# Export script for Create Downloadable Product task

echo "=== Exporting Create Downloadable Product Result ==="

source /workspace/scripts/task_utils.sh

# Verify DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Find the product
TARGET_SKU="VFCS-PAT-001"
PRODUCT_DATA=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null)

PRODUCT_FOUND="false"
PRODUCT_ID=""
VIRTUAL="no"
DOWNLOADABLE="no"
DOWNLOAD_LIMIT=""
DOWNLOAD_EXPIRY=""
DOWNLOAD_FILES_META=""
REGULAR_PRICE=""
SALE_PRICE=""
CATEGORIES=""
SHORT_DESC=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    
    # Get basic fields
    REGULAR_PRICE=$(get_product_price "$PRODUCT_ID")
    SALE_PRICE=$(get_product_sale_price "$PRODUCT_ID")
    
    # Get categories
    CATEGORIES=$(get_product_categories "$PRODUCT_ID")
    
    # Get Short Description
    SHORT_DESC=$(wc_query "SELECT post_excerpt FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1")
    
    # Get Meta fields for Virtual/Downloadable
    VIRTUAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_virtual' LIMIT 1")
    DOWNLOADABLE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_downloadable' LIMIT 1")
    
    # Get Download Settings
    DOWNLOAD_LIMIT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_download_limit' LIMIT 1")
    DOWNLOAD_EXPIRY=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_download_expiry' LIMIT 1")
    
    # Get Downloadable Files (Serialized array)
    # We will export the raw string, Python verifier can check if it contains the filename
    DOWNLOAD_FILES_META=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_downloadable_files' LIMIT 1")
fi

# 3. Escape for JSON
SHORT_DESC_ESC=$(json_escape "$SHORT_DESC")
CATEGORIES_ESC=$(json_escape "$CATEGORIES")
DOWNLOAD_FILES_ESC=$(json_escape "$DOWNLOAD_FILES_META")

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product_id": "$PRODUCT_ID",
    "sku": "$TARGET_SKU",
    "regular_price": "$REGULAR_PRICE",
    "sale_price": "$SALE_PRICE",
    "is_virtual": "$VIRTUAL",
    "is_downloadable": "$DOWNLOADABLE",
    "download_limit": "$DOWNLOAD_LIMIT",
    "download_expiry": "$DOWNLOAD_EXPIRY",
    "downloadable_files_meta": "$DOWNLOAD_FILES_ESC",
    "categories": "$CATEGORIES_ESC",
    "short_description": "$SHORT_DESC_ESC",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json