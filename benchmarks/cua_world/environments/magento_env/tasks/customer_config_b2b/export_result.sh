#!/bin/bash
# Export script for Customer Config B2B task

echo "=== Exporting Customer Config Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the configuration values from the database
# We look specifically for the paths requested in the task
echo "Querying configuration..."

# 1. Street Lines
STREET_LINES=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/address/street_lines' AND scope='default' LIMIT 1" 2>/dev/null)
# 2. Tax/VAT Show
TAXVAT_SHOW=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/address/taxvat_show' AND scope='default' LIMIT 1" 2>/dev/null)
# 3. DOB Show
DOB_SHOW=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/address/dob_show' AND scope='default' LIMIT 1" 2>/dev/null)
# 4. Email Identity
EMAIL_IDENTITY=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/create_account/email_identity' AND scope='default' LIMIT 1" 2>/dev/null)
# 5. Min Password Length
PASS_LEN=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/password/minimum_password_length' AND scope='default' LIMIT 1" 2>/dev/null)
# 6. Character Classes
CHAR_CLASSES=$(magento_query "SELECT value FROM core_config_data WHERE path='customer/password/required_character_classes_number' AND scope='default' LIMIT 1" 2>/dev/null)

echo "Values retrieved:"
echo "  Street Lines: $STREET_LINES"
echo "  Tax/VAT: $TAXVAT_SHOW"
echo "  DOB: $DOB_SHOW"
echo "  Email Identity: $EMAIL_IDENTITY"
echo "  Pass Len: $PASS_LEN"
echo "  Char Classes: $CHAR_CLASSES"

# Get timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Verify the config cache was flushed (optional check, but good for real world)
# We can't easily check cache status from shell, so we rely on DB values.

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/customer_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config": {
        "street_lines": "${STREET_LINES:-}",
        "taxvat_show": "${TAXVAT_SHOW:-}",
        "dob_show": "${DOB_SHOW:-}",
        "email_identity": "${EMAIL_IDENTITY:-}",
        "min_password_length": "${PASS_LEN:-}",
        "required_character_classes_number": "${CHAR_CLASSES:-}"
    }
}
EOF

safe_write_json "$TEMP_JSON" /tmp/customer_config_result.json

echo ""
cat /tmp/customer_config_result.json
echo ""
echo "=== Export Complete ==="