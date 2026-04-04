#!/bin/bash
# Export script for Update Product Inventory task
set -e

echo "=== Exporting Update Product Inventory Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve IDs again (safest)
WBH_ID=$(get_product_by_sku "WBH-001" | cut -f1)
USBC_ID=$(get_product_by_sku "USBC-065" | cut -f1)
SFDJ_ID=$(get_product_by_sku "SFDJ-BLU-32" | cut -f1)

# Function to safely get meta value
get_meta() {
    local pid="$1"
    local key="$2"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$pid AND meta_key='$key' LIMIT 1"
}

# Collect Data for WBH-001 (Headphones)
WBH_STOCK=$(get_product_stock "$WBH_ID")
WBH_LOW_STOCK=$(get_meta "$WBH_ID" "_low_stock_amount")
WBH_STATUS=$(get_product_status "$WBH_ID")

# Collect Data for USBC-065 (Charger)
USBC_STOCK=$(get_product_stock "$USBC_ID")
USBC_STATUS=$(get_product_status "$USBC_ID")

# Collect Data for SFDJ-BLU-32 (Jeans)
SFDJ_STOCK=$(get_product_stock "$SFDJ_ID")
SFDJ_BACKORDERS=$(get_meta "$SFDJ_ID" "_backorders")
SFDJ_STATUS=$(get_product_status "$SFDJ_ID")

# Read Initial State for comparison
INITIAL_STATE="{}"
if [ -f /tmp/initial_inventory.json ]; then
    INITIAL_STATE=$(cat /tmp/initial_inventory.json)
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/inventory_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "products_found": true,
    "initial_state": $INITIAL_STATE,
    "current_state": {
        "headphones": {
            "id": "$WBH_ID",
            "stock": "$WBH_STOCK",
            "low_stock": "$WBH_LOW_STOCK",
            "status": "$WBH_STATUS"
        },
        "charger": {
            "id": "$USBC_ID",
            "stock": "$USBC_STOCK",
            "status": "$USBC_STATUS"
        },
        "jeans": {
            "id": "$SFDJ_ID",
            "stock": "$SFDJ_STOCK",
            "backorders": "$SFDJ_BACKORDERS",
            "status": "$SFDJ_STATUS"
        }
    },
    "timestamp": $(date +%s)
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json