#!/bin/bash
# Export script for Custom Email Template task

echo "=== Exporting Custom Email Template Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_TEMPLATE_COUNT=$(cat /tmp/initial_template_count 2>/dev/null || echo "0")
INITIAL_CONFIG_VALUE=$(cat /tmp/initial_config_value 2>/dev/null || echo "default")
CURRENT_TEMPLATE_COUNT=$(magento_query "SELECT COUNT(*) FROM email_template" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# 1. Query for the specific template by name
# We look for the most recently created one with this name to handle duplicates
TEMPLATE_DATA=$(magento_query "SELECT template_id, template_code, orig_template_code, template_subject, CHAR_LENGTH(template_text) FROM email_template WHERE LOWER(TRIM(template_code))='nestwell order confirmation' ORDER BY template_id DESC LIMIT 1" 2>/dev/null | tail -1)

TEMPLATE_ID=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TEMPLATE_CODE=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $2}')
ORIG_CODE=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $3}')
TEMPLATE_SUBJECT=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $4}')
CONTENT_LEN=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')

TEMPLATE_FOUND="false"
[ -n "$TEMPLATE_ID" ] && TEMPLATE_FOUND="true"

# 2. Get full content for string matching if template found
TEMPLATE_CONTENT=""
if [ "$TEMPLATE_FOUND" = "true" ]; then
    # We use a separate query to avoid awk parsing issues with newlines in content
    # Using python to fetch safely via docker exec if needed, or just simple mysql
    # For simplicity here, we'll try to grep specific strings from the DB directly to avoid massive text transfer
    
    HAS_BRAND=$(magento_query "SELECT COUNT(*) FROM email_template WHERE template_id=$TEMPLATE_ID AND template_text LIKE '%NestWell Home%'" 2>/dev/null | tail -1)
    HAS_EMAIL=$(magento_query "SELECT COUNT(*) FROM email_template WHERE template_id=$TEMPLATE_ID AND template_text LIKE '%support@nestwell-home.com%'" 2>/dev/null | tail -1)
    HAS_VAR=$(magento_query "SELECT COUNT(*) FROM email_template WHERE template_id=$TEMPLATE_ID AND template_text LIKE '%{{var order.increment_id}}%'" 2>/dev/null | tail -1)
else
    HAS_BRAND="0"
    HAS_EMAIL="0"
    HAS_VAR="0"
fi

# 3. Check System Configuration
# We need to see if sales_email/order/template is set to the TEMPLATE_ID
CONFIG_VALUE=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/order/template'" 2>/dev/null | tail -1 || echo "")
CONFIG_SCOPE=$(magento_query "SELECT scope FROM core_config_data WHERE path='sales_email/order/template'" 2>/dev/null | tail -1 || echo "default")

echo "Template Found: $TEMPLATE_FOUND (ID: $TEMPLATE_ID)"
echo "Config Value: $CONFIG_VALUE (Scope: $CONFIG_SCOPE)"

# Escape strings for JSON
TEMPLATE_CODE_ESC=$(echo "$TEMPLATE_CODE" | sed 's/"/\\"/g')
TEMPLATE_SUBJECT_ESC=$(echo "$TEMPLATE_SUBJECT" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/email_template_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_template_count": ${INITIAL_TEMPLATE_COUNT:-0},
    "current_template_count": ${CURRENT_TEMPLATE_COUNT:-0},
    "template_found": $TEMPLATE_FOUND,
    "template_id": "${TEMPLATE_ID:-}",
    "template_code": "$TEMPLATE_CODE_ESC",
    "orig_template_code": "${ORIG_CODE:-}",
    "template_subject": "$TEMPLATE_SUBJECT_ESC",
    "content_has_brand": $([ "${HAS_BRAND:-0}" -gt 0 ] && echo "true" || echo "false"),
    "content_has_email": $([ "${HAS_EMAIL:-0}" -gt 0 ] && echo "true" || echo "false"),
    "content_has_var": $([ "${HAS_VAR:-0}" -gt 0 ] && echo "true" || echo "false"),
    "initial_config_value": "${INITIAL_CONFIG_VALUE:-}",
    "current_config_value": "${CONFIG_VALUE:-}",
    "config_scope": "${CONFIG_SCOPE:-}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/email_template_result.json 2>/dev/null || sudo rm -f /tmp/email_template_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/email_template_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/email_template_result.json
chmod 666 /tmp/email_template_result.json 2>/dev/null || sudo chmod 666 /tmp/email_template_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/email_template_result.json"
cat /tmp/email_template_result.json
echo "=== Export Complete ==="