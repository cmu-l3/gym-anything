#!/bin/bash
# Export script for Sales Email Copy Config task

echo "=== Exporting Sales Email Copy Config Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the configuration table for the specific paths
# We use magento_query which returns tab-separated values without headers
# Path 1: Order Copy To
ORDER_COPY_TO=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/order/copy_to'" 2>/dev/null | tail -1)

# Path 2: Order Copy Method
ORDER_COPY_METHOD=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/order/copy_method'" 2>/dev/null | tail -1)

# Path 3: Invoice Copy To
INVOICE_COPY_TO=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/invoice/copy_to'" 2>/dev/null | tail -1)

# Path 4: Invoice Copy Method
INVOICE_COPY_METHOD=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/invoice/copy_method'" 2>/dev/null | tail -1)

# Get timestamps to ensure data was changed recently
# This is harder for specific rows, so we rely on the logic that we wiped them in setup
# If they exist now, they must have been created by the agent.

echo "Order Copy To: $ORDER_COPY_TO"
echo "Order Method: $ORDER_COPY_METHOD"
echo "Invoice Copy To: $INVOICE_COPY_TO"
echo "Invoice Method: $INVOICE_COPY_METHOD"

# Verify app was running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/sales_email_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_copy_to": "${ORDER_COPY_TO:-}",
    "order_copy_method": "${ORDER_COPY_METHOD:-}",
    "invoice_copy_to": "${INVOICE_COPY_TO:-}",
    "invoice_copy_method": "${INVOICE_COPY_METHOD:-}",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save safely
safe_write_json "$TEMP_JSON" /tmp/sales_email_result.json

echo ""
cat /tmp/sales_email_result.json
echo ""
echo "=== Export Complete ==="