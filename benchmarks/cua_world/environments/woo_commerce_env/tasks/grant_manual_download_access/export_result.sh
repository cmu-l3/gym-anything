#!/bin/bash
# Export script for Grant Manual Download Access task

echo "=== Exporting Grant Manual Download Access Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the Digital Product
DIGITAL_PROD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_title='Exclusive Digital Supplement' LIMIT 1" 2>/dev/null)
DIGITAL_IS_DOWNLOADABLE="false"
DIGITAL_IS_VIRTUAL="false"
DIGITAL_FILE_PATH=""

if [ -n "$DIGITAL_PROD_ID" ]; then
    DIGITAL_IS_DOWNLOADABLE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$DIGITAL_PROD_ID AND meta_key='_downloadable' LIMIT 1" 2>/dev/null)
    DIGITAL_IS_VIRTUAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$DIGITAL_PROD_ID AND meta_key='_virtual' LIMIT 1" 2>/dev/null)
    DIGITAL_FILE_PATH=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$DIGITAL_PROD_ID AND meta_key='_file_paths' LIMIT 1" 2>/dev/null)
fi

# 2. Find the Physical Product
PHYSICAL_PROD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_title='Physical Training Manual' LIMIT 1" 2>/dev/null)
PHYSICAL_IS_DOWNLOADABLE="false"

if [ -n "$PHYSICAL_PROD_ID" ]; then
    PHYSICAL_IS_DOWNLOADABLE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PHYSICAL_PROD_ID AND meta_key='_downloadable' LIMIT 1" 2>/dev/null)
fi

# 3. Find the Order (We look for the newest completed order that contains the Physical Product)
# Query logic: Get newest order ID that has a line item with product_id = PHYSICAL_PROD_ID
ORDER_ID=""
ORDER_STATUS=""
ORDER_CONTAINS_PHYSICAL="false"
ORDER_CONTAINS_DIGITAL_ITEM="false"

if [ -n "$PHYSICAL_PROD_ID" ]; then
    ORDER_ID=$(wc_query "SELECT order_id FROM wp_woocommerce_order_itemmeta WHERE meta_key='_product_id' AND meta_value=$PHYSICAL_PROD_ID ORDER BY order_item_id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$ORDER_ID" ]; then
        ORDER_CONTAINS_PHYSICAL="true"
        ORDER_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$ORDER_ID" 2>/dev/null)
        
        # Check if Digital Product was accidentally added as a line item (Anti-gaming)
        if [ -n "$DIGITAL_PROD_ID" ]; then
            DIGITAL_ITEM_CHECK=$(wc_query "SELECT order_item_id FROM wp_woocommerce_order_itemmeta WHERE meta_key='_product_id' AND meta_value=$DIGITAL_PROD_ID AND order_id=$ORDER_ID LIMIT 1" 2>/dev/null)
            if [ -n "$DIGITAL_ITEM_CHECK" ]; then
                ORDER_CONTAINS_DIGITAL_ITEM="true"
            fi
        fi
    fi
fi

# 4. Check Permissions (The core goal)
PERMISSION_GRANTED="false"
DOWNLOADS_REMAINING=""

if [ -n "$ORDER_ID" ] && [ -n "$DIGITAL_PROD_ID" ]; then
    # wp_woocommerce_downloadable_product_permissions table
    PERM_ROW=$(wc_query "SELECT downloads_remaining FROM wp_woocommerce_downloadable_product_permissions WHERE order_id=$ORDER_ID AND product_id=$DIGITAL_PROD_ID LIMIT 1" 2>/dev/null)
    
    if [ -n "$PERM_ROW" ]; then
        PERMISSION_GRANTED="true"
        DOWNLOADS_REMAINING="$PERM_ROW"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "digital_product": {
        "found": $([ -n "$DIGITAL_PROD_ID" ] && echo "true" || echo "false"),
        "id": "${DIGITAL_PROD_ID:-null}",
        "is_downloadable": "$DIGITAL_IS_DOWNLOADABLE",
        "is_virtual": "$DIGITAL_IS_VIRTUAL",
        "has_file_path": $([ -n "$DIGITAL_FILE_PATH" ] && echo "true" || echo "false")
    },
    "physical_product": {
        "found": $([ -n "$PHYSICAL_PROD_ID" ] && echo "true" || echo "false"),
        "id": "${PHYSICAL_PROD_ID:-null}",
        "is_downloadable": "$PHYSICAL_IS_DOWNLOADABLE"
    },
    "order": {
        "found": $([ -n "$ORDER_ID" ] && echo "true" || echo "false"),
        "id": "${ORDER_ID:-null}",
        "status": "$ORDER_STATUS",
        "contains_physical_item": $ORDER_CONTAINS_PHYSICAL,
        "contains_digital_item_line": $ORDER_CONTAINS_DIGITAL_ITEM
    },
    "permission": {
        "granted": $PERMISSION_GRANTED,
        "downloads_remaining": "${DOWNLOADS_REMAINING:-0}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="