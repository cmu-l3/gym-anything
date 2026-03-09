#!/bin/bash
# Export script for Update Product Price task

echo "=== Exporting Update Product Price Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "product_found": false, "price_changed": false, "product": {}}' > /tmp/update_product_price_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get target product ID
TARGET_ID=$(cat /tmp/target_product_id 2>/dev/null)
ORIG_REGULAR=$(cat /tmp/original_regular_price 2>/dev/null || echo "79.99")
ORIG_SALE=$(cat /tmp/original_sale_price 2>/dev/null || echo "")

echo "Target product ID: $TARGET_ID"
echo "Original regular price: $ORIG_REGULAR"
echo "Original sale price: $ORIG_SALE"

# Get current state of target product
PRODUCT_FOUND="false"
CURRENT_REGULAR=""
CURRENT_SALE=""
PRODUCT_NAME=""
PRODUCT_SKU=""
PRICE_CHANGED="false"

if [ -n "$TARGET_ID" ]; then
    PRODUCT_NAME=$(get_product_name "$TARGET_ID" 2>/dev/null)
    PRODUCT_SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$TARGET_ID AND meta_key='_sku' LIMIT 1" 2>/dev/null)
    CURRENT_REGULAR=$(get_product_price "$TARGET_ID" 2>/dev/null)
    CURRENT_SALE=$(get_product_sale_price "$TARGET_ID" 2>/dev/null)

    if [ -n "$PRODUCT_NAME" ]; then
        PRODUCT_FOUND="true"
    fi

    if [ "$CURRENT_REGULAR" != "$ORIG_REGULAR" ] || [ -n "$CURRENT_SALE" -a "$CURRENT_SALE" != "$ORIG_SALE" ]; then
        PRICE_CHANGED="true"
    fi

    echo "Current state: Name='$PRODUCT_NAME', SKU='$PRODUCT_SKU', Regular='$CURRENT_REGULAR', Sale='$CURRENT_SALE', Changed=$PRICE_CHANGED"
else
    echo "Target product ID not recorded"
fi

# Escape special characters for JSON (handles quotes, backslashes, newlines, etc.)
PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")
PRODUCT_SKU_ESC=$(json_escape "$PRODUCT_SKU")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/update_product_price_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "price_changed": $PRICE_CHANGED,
    "product": {
        "id": "$TARGET_ID",
        "name": "$PRODUCT_NAME_ESC",
        "sku": "$PRODUCT_SKU_ESC",
        "regular_price": "$CURRENT_REGULAR",
        "sale_price": "$CURRENT_SALE",
        "original_regular_price": "$ORIG_REGULAR",
        "original_sale_price": "$ORIG_SALE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/update_product_price_result.json

echo ""
cat /tmp/update_product_price_result.json
echo ""
echo "=== Export Complete ==="
