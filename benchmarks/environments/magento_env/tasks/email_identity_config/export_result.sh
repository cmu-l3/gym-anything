#!/bin/bash
# Export script for Email Identity Configuration task

echo "=== Exporting Email Identity Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper function to get config value
get_config() {
    local path="$1"
    # Get value from database (scope='default' typically, or just take the last entry if multiple)
    magento_query "SELECT value FROM core_config_data WHERE path='$path' ORDER BY config_id DESC LIMIT 1" 2>/dev/null
}

# 1. Get Identity Definitions
SALES_NAME=$(get_config "trans_email/ident_sales/name")
SALES_EMAIL=$(get_config "trans_email/ident_sales/email")
SUPPORT_NAME=$(get_config "trans_email/ident_support/name")
SUPPORT_EMAIL=$(get_config "trans_email/ident_support/email")

# 2. Get Sales Email Config
ORDER_IDENTITY=$(get_config "sales_email/order/identity")
ORDER_COPY_TO=$(get_config "sales_email/order/copy_to")
INVOICE_IDENTITY=$(get_config "sales_email/invoice/identity")

# 3. Get Contact Us Config
CONTACT_RECIPIENT=$(get_config "contact/email/recipient_email")
CONTACT_SENDER=$(get_config "contact/email/sender_email_identity")

echo "--- Extracted Configuration ---"
echo "Sales Identity: $SALES_NAME <$SALES_EMAIL>"
echo "Support Identity: $SUPPORT_NAME <$SUPPORT_EMAIL>"
echo "Order Identity: $ORDER_IDENTITY"
echo "Order Copy To: $ORDER_COPY_TO"
echo "Invoice Identity: $INVOICE_IDENTITY"
echo "Contact Recipient: $CONTACT_RECIPIENT"
echo "Contact Sender: $CONTACT_SENDER"

# Escape for JSON
SALES_NAME_ESC=$(echo "$SALES_NAME" | sed 's/"/\\"/g')
SALES_EMAIL_ESC=$(echo "$SALES_EMAIL" | sed 's/"/\\"/g')
SUPPORT_NAME_ESC=$(echo "$SUPPORT_NAME" | sed 's/"/\\"/g')
SUPPORT_EMAIL_ESC=$(echo "$SUPPORT_EMAIL" | sed 's/"/\\"/g')
ORDER_COPY_TO_ESC=$(echo "$ORDER_COPY_TO" | sed 's/"/\\"/g')
CONTACT_RECIPIENT_ESC=$(echo "$CONTACT_RECIPIENT" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/email_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sales_name": "$SALES_NAME_ESC",
    "sales_email": "$SALES_EMAIL_ESC",
    "support_name": "$SUPPORT_NAME_ESC",
    "support_email": "$SUPPORT_EMAIL_ESC",
    "order_identity": "$ORDER_IDENTITY",
    "order_copy_to": "$ORDER_COPY_TO_ESC",
    "invoice_identity": "$INVOICE_IDENTITY",
    "contact_recipient": "$CONTACT_RECIPIENT_ESC",
    "contact_sender": "$CONTACT_SENDER",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/email_config_result.json

echo ""
cat /tmp/email_config_result.json
echo ""
echo "=== Export Complete ==="