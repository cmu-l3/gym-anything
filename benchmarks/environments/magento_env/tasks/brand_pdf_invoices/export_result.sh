#!/bin/bash
# Export script for Brand PDF Invoices task

echo "=== Exporting Brand PDF Invoices Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Configuration in Database
# Note: scope='default' and scope_id=0 for global settings
LOGO_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/identity/logo' AND scope='default'" 2>/dev/null)
LOGO_HTML_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/identity/logo_html' AND scope='default'" 2>/dev/null)
ADDRESS_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/identity/address' AND scope='default'" 2>/dev/null)

echo "Config Values Found:"
echo "Logo: $LOGO_VAL"
echo "Logo HTML: $LOGO_HTML_VAL"
echo "Address: $ADDRESS_VAL"

# 2. Check for Invoices created AFTER task start
# sales_invoice table has 'created_at' timestamp. We need to check if any invoice exists created > task start
# We'll fetch the most recent invoice and its timestamp
LATEST_INVOICE=$(magento_query "SELECT entity_id, increment_id, created_at, order_id FROM sales_invoice ORDER BY entity_id DESC LIMIT 1" 2>/dev/null)
INVOICE_ID=""
INVOICE_TIMESTAMP="0"

if [ -n "$LATEST_INVOICE" ]; then
    INVOICE_ID=$(echo "$LATEST_INVOICE" | awk -F'\t' '{print $1}')
    INVOICE_CREATED_AT=$(echo "$LATEST_INVOICE" | awk -F'\t' '{print $3}')
    
    # Convert MySQL timestamp to unix epoch for comparison
    INVOICE_TIMESTAMP=$(date -d "$INVOICE_CREATED_AT" +%s 2>/dev/null || echo "0")
    
    echo "Latest Invoice: ID=$INVOICE_ID Created=$INVOICE_CREATED_AT (Epoch: $INVOICE_TIMESTAMP)"
else
    echo "No invoices found in system."
fi

# Determine if invoice was created during task
INVOICE_CREATED_DURING_TASK="false"
if [ "$INVOICE_TIMESTAMP" -gt "$TASK_START_TIME" ]; then
    INVOICE_CREATED_DURING_TASK="true"
fi

# Escape address for JSON (handle newlines)
# We use python to safely JSON dump the string to avoid bash escaping hell
ADDRESS_JSON=$(python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$ADDRESS_VAL")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/brand_pdf_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "logo_config_value": "$(echo "$LOGO_VAL" | sed 's/"/\\"/g')",
    "logo_html_config_value": "$(echo "$LOGO_HTML_VAL" | sed 's/"/\\"/g')",
    "address_config_value": $ADDRESS_JSON,
    "latest_invoice_id": "$INVOICE_ID",
    "invoice_created_during_task": $INVOICE_CREATED_DURING_TASK,
    "invoice_timestamp": $INVOICE_TIMESTAMP
}
EOF

safe_write_json "$TEMP_JSON" /tmp/brand_pdf_result.json
echo ""
cat /tmp/brand_pdf_result.json
echo ""
echo "=== Export Complete ==="