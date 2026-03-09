#!/bin/bash
# Export script for Store Branding Config task

echo "=== Exporting Store Branding Config Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to get config value
get_config() {
    local path="$1"
    # Query for default scope (scope_id=0) or default scope type
    magento_query "SELECT value FROM core_config_data WHERE path='$path' AND (scope='default' OR scope_id=0) ORDER BY config_id DESC LIMIT 1" 2>/dev/null
}

# 1. Store Information
STORE_NAME=$(get_config "general/store_information/name")
STORE_PHONE=$(get_config "general/store_information/phone")
STORE_HOURS=$(get_config "general/store_information/hours")
STORE_COUNTRY=$(get_config "general/store_information/country_id")
STORE_REGION_ID=$(get_config "general/store_information/region_id")
STORE_REGION=$(get_config "general/store_information/region") # In case text is used
STORE_ZIP=$(get_config "general/store_information/postcode")
STORE_CITY=$(get_config "general/store_information/city")
STORE_STREET=$(get_config "general/store_information/street_line1")

# 2. Emails
EMAIL_GEN_NAME=$(get_config "trans_email/ident_general/name")
EMAIL_GEN_EMAIL=$(get_config "trans_email/ident_general/email")
EMAIL_SALES_NAME=$(get_config "trans_email/ident_sales/name")
EMAIL_SALES_EMAIL=$(get_config "trans_email/ident_sales/email")
EMAIL_SUP_NAME=$(get_config "trans_email/ident_support/name")
EMAIL_SUP_EMAIL=$(get_config "trans_email/ident_support/email")

# 3. Design
HEAD_TITLE=$(get_config "design/head/default_title")
HEAD_DESC=$(get_config "design/head/default_description")
HEADER_WELCOME=$(get_config "design/header/welcome")
FOOTER_COPY=$(get_config "design/footer/copyright")

# Check if config actually changed
magento_query "SELECT path, value FROM core_config_data WHERE path LIKE 'general/%' OR path LIKE 'trans_email/%' OR path LIKE 'design/%'" > /tmp/final_config_dump.txt
FINAL_HASH=$(md5sum /tmp/final_config_dump.txt | awk '{print $1}')
INITIAL_HASH=$(cat /tmp/initial_config_hash.txt | awk '{print $1}' 2>/dev/null || echo "")

CONFIG_CHANGED="false"
if [ "$FINAL_HASH" != "$INITIAL_HASH" ]; then
    CONFIG_CHANGED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/branding_result.XXXXXX.json)

# We use python to dump json to avoid shell escaping hell with complex strings
python3 -c "
import json
import sys

data = {
    'store_info': {
        'name': '''$STORE_NAME''',
        'phone': '''$STORE_PHONE''',
        'hours': '''$STORE_HOURS''',
        'country': '''$STORE_COUNTRY''',
        'region_id': '''$STORE_REGION_ID''',
        'region': '''$STORE_REGION''',
        'zip': '''$STORE_ZIP''',
        'city': '''$STORE_CITY''',
        'street': '''$STORE_STREET'''
    },
    'emails': {
        'general_name': '''$EMAIL_GEN_NAME''',
        'general_email': '''$EMAIL_GEN_EMAIL''',
        'sales_name': '''$EMAIL_SALES_NAME''',
        'sales_email': '''$EMAIL_SALES_EMAIL''',
        'support_name': '''$EMAIL_SUP_NAME''',
        'support_email': '''$EMAIL_SUP_EMAIL'''
    },
    'design': {
        'head_title': '''$HEAD_TITLE''',
        'head_desc': '''$HEAD_DESC''',
        'welcome': '''$HEADER_WELCOME''',
        'copyright': '''$FOOTER_COPY'''
    },
    'meta': {
        'config_changed': $CONFIG_CHANGED,
        'task_start': $TASK_START,
        'task_end': $TASK_END
    }
}
print(json.dumps(data))
" > "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/branding_result.json

echo ""
echo "Result exported to /tmp/branding_result.json"
echo "=== Export Complete ==="