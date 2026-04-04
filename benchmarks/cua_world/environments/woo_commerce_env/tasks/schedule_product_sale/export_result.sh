#!/bin/bash
set -e
echo "=== Exporting schedule_product_sale result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get product ID
PRODUCT_ID=$(cat /tmp/task_product_id.txt 2>/dev/null)
if [ -z "$PRODUCT_ID" ]; then
    # Fallback: look up by SKU
    PRODUCT_INFO=$(get_product_by_sku "WBH-001")
    PRODUCT_ID=$(echo "$PRODUCT_INFO" | awk '{print $1}')
fi

PRODUCT_FOUND="false"
SALE_PRICE=""
SALE_FROM=""
SALE_TO=""
REGULAR_PRICE=""
POST_MODIFIED=""

if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
    
    # Query current state from database
    SALE_PRICE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price' LIMIT 1")
    SALE_FROM=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price_dates_from' LIMIT 1")
    SALE_TO=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price_dates_to' LIMIT 1")
    REGULAR_PRICE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_regular_price' LIMIT 1")
    
    # Get modification time (Unix timestamp)
    POST_MODIFIED=$(wc_query "SELECT UNIX_TIMESTAMP(post_modified) FROM wp_posts WHERE ID=$PRODUCT_ID LIMIT 1")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product_id": "${PRODUCT_ID:-0}",
    "sale_price": "${SALE_PRICE:-}",
    "sale_date_from": "${SALE_FROM:-0}",
    "sale_date_to": "${SALE_TO:-0}",
    "regular_price": "${REGULAR_PRICE:-}",
    "post_modified": ${POST_MODIFIED:-0},
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="