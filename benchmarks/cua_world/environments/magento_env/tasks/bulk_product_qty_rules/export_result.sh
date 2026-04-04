#!/bin/bash
# Export script for Bulk Product Quantity Rules task

echo "=== Exporting Bulk Product Quantity Rules Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TARGET_SKU="TSHIRT-001"

# Check if product exists and get ID
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

PRODUCT_FOUND="false"
MIN_SALE_QTY="0"
MAX_SALE_QTY="0"
ENABLE_QTY_INCREMENTS="0"
QTY_INCREMENTS="0"
USE_CONFIG_MIN="1"
USE_CONFIG_MAX="1"
USE_CONFIG_INC="1"
USE_CONFIG_INC_QTY="1"

if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
    
    # Query stock item table for inventory rules
    # We select the specific columns related to the task
    STOCK_DATA=$(magento_query "SELECT min_sale_qty, max_sale_qty, enable_qty_increments, qty_increments, use_config_min_sale_qty, use_config_max_sale_qty, use_config_enable_qty_increments, use_config_qty_increments FROM cataloginventory_stock_item WHERE product_id=$PRODUCT_ID" 2>/dev/null | tail -1)
    
    MIN_SALE_QTY=$(echo "$STOCK_DATA" | awk -F'\t' '{print $1}')
    MAX_SALE_QTY=$(echo "$STOCK_DATA" | awk -F'\t' '{print $2}')
    ENABLE_QTY_INCREMENTS=$(echo "$STOCK_DATA" | awk -F'\t' '{print $3}')
    QTY_INCREMENTS=$(echo "$STOCK_DATA" | awk -F'\t' '{print $4}')
    
    # Also capture "use_config" flags - if these are 1, the agent didn't successfully override the global settings
    USE_CONFIG_MIN=$(echo "$STOCK_DATA" | awk -F'\t' '{print $5}')
    USE_CONFIG_MAX=$(echo "$STOCK_DATA" | awk -F'\t' '{print $6}')
    USE_CONFIG_INC=$(echo "$STOCK_DATA" | awk -F'\t' '{print $7}')
    USE_CONFIG_INC_QTY=$(echo "$STOCK_DATA" | awk -F'\t' '{print $8}')
fi

echo "Product ID: $PRODUCT_ID"
echo "Found: $PRODUCT_FOUND"
echo "Min Qty: $MIN_SALE_QTY (Config: $USE_CONFIG_MIN)"
echo "Max Qty: $MAX_SALE_QTY (Config: $USE_CONFIG_MAX)"
echo "Enable Inc: $ENABLE_QTY_INCREMENTS (Config: $USE_CONFIG_INC)"
echo "Inc Qty: $QTY_INCREMENTS (Config: $USE_CONFIG_INC_QTY)"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/bulk_rules_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "sku": "$TARGET_SKU",
    "min_sale_qty": "${MIN_SALE_QTY:-0}",
    "max_sale_qty": "${MAX_SALE_QTY:-0}",
    "enable_qty_increments": "${ENABLE_QTY_INCREMENTS:-0}",
    "qty_increments": "${QTY_INCREMENTS:-0}",
    "use_config_min": "${USE_CONFIG_MIN:-1}",
    "use_config_max": "${USE_CONFIG_MAX:-1}",
    "use_config_inc": "${USE_CONFIG_INC:-1}",
    "use_config_inc_qty": "${USE_CONFIG_INC_QTY:-1}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/bulk_rules_result.json

echo ""
cat /tmp/bulk_rules_result.json
echo ""
echo "=== Export Complete ==="