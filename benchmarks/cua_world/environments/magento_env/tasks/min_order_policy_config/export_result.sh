#!/bin/bash
# Export script for Minimum Order Policy task

echo "=== Exporting Minimum Order Policy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the core_config_data table for the relevant paths
# Paths:
# sales/minimum_order/active
# sales/minimum_order/amount
# sales/minimum_order/tax_include
# sales/minimum_order/include_discount_amount
# sales/minimum_order/description
# sales/minimum_order/error_message

echo "Querying configuration..."

CONFIG_ACTIVE=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/active'" 2>/dev/null | tail -1)
CONFIG_AMOUNT=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/amount'" 2>/dev/null | tail -1)
CONFIG_TAX=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/tax_include'" 2>/dev/null | tail -1)
CONFIG_DISCOUNT=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/include_discount_amount'" 2>/dev/null | tail -1)
CONFIG_DESC=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/description'" 2>/dev/null | tail -1)
CONFIG_ERROR=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/minimum_order/error_message'" 2>/dev/null | tail -1)

# Retrieve initial state to check for changes
INITIAL_ACTIVE=$(cat /tmp/initial_config_active 2>/dev/null || echo "0")

# Debug output
echo "Config State:"
echo "  Active: $CONFIG_ACTIVE (Initial: $INITIAL_ACTIVE)"
echo "  Amount: $CONFIG_AMOUNT"
echo "  Tax Include: $CONFIG_TAX"
echo "  Discount Include: $CONFIG_DISCOUNT"
echo "  Description: $CONFIG_DESC"
echo "  Error Msg: $CONFIG_ERROR"

# Escape strings for JSON
CONFIG_DESC_ESC=$(echo "$CONFIG_DESC" | sed 's/"/\\"/g' | tr -d '\n')
CONFIG_ERROR_ESC=$(echo "$CONFIG_ERROR" | sed 's/"/\\"/g' | tr -d '\n')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/min_order_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_active": "${INITIAL_ACTIVE:-0}",
    "config_active": "${CONFIG_ACTIVE:-0}",
    "config_amount": "${CONFIG_AMOUNT:-0}",
    "config_tax_include": "${CONFIG_TAX:-0}",
    "config_discount_include": "${CONFIG_DISCOUNT:-0}",
    "config_description": "$CONFIG_DESC_ESC",
    "config_error_message": "$CONFIG_ERROR_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/min_order_result.json

echo ""
cat /tmp/min_order_result.json
echo ""
echo "=== Export Complete ==="