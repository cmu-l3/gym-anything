#!/bin/bash
# Export script for Cookie Consent Compliance task

echo "=== Exporting Cookie Consent Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# 1. Check CMS Page
PAGE_DATA=$(magento_query "SELECT page_id, title, is_active FROM cms_page WHERE identifier='privacy-policy-2026' LIMIT 1" 2>/dev/null | tail -1)
PAGE_FOUND="false"
PAGE_ACTIVE="false"
PAGE_TITLE=""

if [ -n "$PAGE_DATA" ]; then
    PAGE_FOUND="true"
    PAGE_ID=$(echo "$PAGE_DATA" | awk -F'\t' '{print $1}')
    PAGE_TITLE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $2}')
    IS_ACTIVE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $3}')
    
    if [ "$IS_ACTIVE" == "1" ]; then
        PAGE_ACTIVE="true"
    fi
fi

# 2. Check Configuration Settings
# We check for the value. If multiple scopes exist, we look for at least one matching row.

# Cookie Restriction Mode (Yes = 1)
RESTRICTION_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='web/cookie/cookie_restriction' ORDER BY config_id DESC LIMIT 1" 2>/dev/null | tail -1)

# Cookie Lifetime (86400)
LIFETIME_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='web/cookie/cookie_lifetime' ORDER BY config_id DESC LIMIT 1" 2>/dev/null | tail -1)

# HttpOnly (Yes = 1)
HTTPONLY_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='web/cookie/cookie_httponly' ORDER BY config_id DESC LIMIT 1" 2>/dev/null | tail -1)

# Footer Copyright
FOOTER_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path='design/footer/copyright' ORDER BY config_id DESC LIMIT 1" 2>/dev/null | tail -1)

# Escape strings for JSON
PAGE_TITLE_ESC=$(echo "$PAGE_TITLE" | sed 's/"/\\"/g')
FOOTER_VAL_ESC=$(echo "$FOOTER_VAL" | sed 's/"/\\"/g')

# Create JSON
TEMP_JSON=$(mktemp /tmp/cookie_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "page_found": $PAGE_FOUND,
    "page_active": $PAGE_ACTIVE,
    "page_title": "$PAGE_TITLE_ESC",
    "config_restriction": "${RESTRICTION_VAL:-0}",
    "config_lifetime": "${LIFETIME_VAL:-0}",
    "config_httponly": "${HTTPONLY_VAL:-0}",
    "config_footer": "$FOOTER_VAL_ESC",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/cookie_consent_result.json

echo ""
cat /tmp/cookie_consent_result.json
echo ""
echo "=== Export Complete ==="