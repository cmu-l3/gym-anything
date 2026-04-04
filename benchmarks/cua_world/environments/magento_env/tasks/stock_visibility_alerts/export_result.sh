#!/bin/bash
# Export script for Stock Visibility & Alerts task

echo "=== Exporting Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the configuration table for the relevant paths
# We select path and value. If there are multiple scopes, we'll capture them all.
# Ideally we want the Default Config (scope_id=0) or Main Website.
echo "Querying configuration..."

# 1. Show Out of Stock
SHOW_OOS=$(magento_query "SELECT value FROM core_config_data WHERE path='cataloginventory/options/show_out_of_stock' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)

# 2. Stock Threshold
THRESHOLD=$(magento_query "SELECT value FROM core_config_data WHERE path='cataloginventory/options/stock_threshold_qty' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)

# 3. Allow Stock Alert
STOCK_ALERT=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/productalert/allow_stock' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)

# 4. Allow Price Alert
PRICE_ALERT=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/productalert/allow_price' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)

# 5. Stock Alert Identity
# Note: The UI label "Customer Support" maps to value 'support' in DB
IDENTITY=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/productalert/email_stock_identity' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)

# Debug output
echo "Config Values Found:"
echo "  show_out_of_stock: $SHOW_OOS"
echo "  stock_threshold_qty: $THRESHOLD"
echo "  allow_stock: $STOCK_ALERT"
echo "  allow_price: $PRICE_ALERT"
echo "  email_stock_identity: $IDENTITY"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config": {
        "show_out_of_stock": "${SHOW_OOS:-0}",
        "stock_threshold": "${THRESHOLD:-}",
        "allow_stock_alert": "${STOCK_ALERT:-0}",
        "allow_price_alert": "${PRICE_ALERT:-0}",
        "stock_email_identity": "${IDENTITY:-}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="