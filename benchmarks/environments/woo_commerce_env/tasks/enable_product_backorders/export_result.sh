#!/bin/bash
# Export script for Enable Product Backorders task

echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup info
PRODUCT_ID=$(cat /tmp/target_product_id.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

if [ -z "$PRODUCT_ID" ]; then
    # Fallback lookup if file missing
    PRODUCT_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
fi

echo "Analyzing Product ID: $PRODUCT_ID"

# 1. Fetch Product Meta Data
# We query specific meta keys relevant to the task
# _backorders: 'no', 'notify', 'yes'
# _low_stock_amount: integer or empty
# _manage_stock: 'yes', 'no'
# _stock_status: 'instock', 'outofstock', 'onbackorder'

BACKORDERS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_backorders' LIMIT 1")
LOW_STOCK=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_low_stock_amount' LIMIT 1")
MANAGE_STOCK=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_manage_stock' LIMIT 1")
STOCK_STATUS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_stock_status' LIMIT 1")

# 2. Check Modification Time
# Get the last modified date in GMT and convert to timestamp
LAST_MODIFIED_GMT=$(wc_query "SELECT post_modified_gmt FROM wp_posts WHERE ID=$PRODUCT_ID")
# Convert MySQL datetime to unix timestamp (assuming UTC/GMT)
MODIFIED_TS=$(date -d "$LAST_MODIFIED_GMT" +%s 2>/dev/null || echo "0")

# 3. Check for Collateral Damage (Anti-Gaming)
# Count how many OTHER products were modified since task start
OTHER_MODS=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND ID != $PRODUCT_ID AND post_modified_gmt > FROM_UNIXTIME($TASK_START)")

# 4. Construct JSON Result
# Using python for safe JSON construction to handle empty values/strings
python3 -c "
import json
import os

result = {
    'product_found': True if '$PRODUCT_ID' else False,
    'product_id': '$PRODUCT_ID',
    'backorders': '$BACKORDERS',
    'low_stock_amount': '$LOW_STOCK',
    'manage_stock': '$MANAGE_STOCK',
    'stock_status': '$STOCK_STATUS',
    'modified_timestamp': $MODIFIED_TS,
    'task_start_timestamp': $TASK_START,
    'other_products_modified_count': int('$OTHER_MODS') if '$OTHER_MODS'.isdigit() else 0,
    'export_timestamp': $EXPORT_TIME,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="