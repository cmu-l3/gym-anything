#!/bin/bash
# Export script for Support Tools Config task

echo "=== Exporting Support Tools Config Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper function to get config value
get_config_value() {
    local path="$1"
    # Query database for the specific path
    # core_config_data stores values for paths. 
    # Scope is usually 'default' (scope_id=0) for global settings
    magento_query "SELECT value FROM core_config_data WHERE path='$path' ORDER BY config_id DESC LIMIT 1" 2>/dev/null
}

# 1. Login as Customer Enabled
# Path: login_as_customer/general/enabled
LAC_ENABLED=$(get_config_value "login_as_customer/general/enabled")

# 2. UI Title
# Path: login_as_customer/general/ui_title
LAC_TITLE=$(get_config_value "login_as_customer/general/ui_title")

# 3. Online Minutes Interval
# Path: customer/online/interval
ONLINE_INTERVAL=$(get_config_value "customer/online/interval")

# 4. Contact Email
# Path: contact/contact/recipient_email
CONTACT_EMAIL=$(get_config_value "contact/contact/recipient_email")

echo "Extracted Values:"
echo "  LAC Enabled: $LAC_ENABLED"
echo "  LAC Title: $LAC_TITLE"
echo "  Online Interval: $ONLINE_INTERVAL"
echo "  Contact Email: $CONTACT_EMAIL"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/support_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "lac_enabled": "${LAC_ENABLED:-0}",
    "lac_title": "${LAC_TITLE:-}",
    "online_interval": "${ONLINE_INTERVAL:-}",
    "contact_email": "${CONTACT_EMAIL:-}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/support_config_result.json

echo ""
cat /tmp/support_config_result.json
echo ""
echo "=== Export Complete ==="