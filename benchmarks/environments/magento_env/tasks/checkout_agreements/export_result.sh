#!/bin/bash
# Export script for Checkout Agreements task

echo "=== Exporting Checkout Agreements Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_agreement_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM checkout_agreement" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Agreements count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# 1. Check Configuration (Enable Terms and Conditions)
# The path is 'checkout/options/enable_agreements'
CONFIG_VALUE=$(magento_query "SELECT value FROM core_config_data WHERE path='checkout/options/enable_agreements'" 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "Config checkout/options/enable_agreements: '$CONFIG_VALUE'"

# 2. Check Agreement 1: Handmade Goods
AGREEMENT1_DATA=$(magento_query "SELECT agreement_id, name, is_active, is_html, mode, checkbox_text, content FROM checkout_agreement WHERE LOWER(name) LIKE '%handmade%' LIMIT 1" 2>/dev/null | tail -1)

A1_FOUND="false"
A1_ID=""
A1_NAME=""
A1_ACTIVE=""
A1_HTML=""
A1_MODE=""
A1_TEXT=""
A1_CONTENT=""
A1_STORE_COUNT="0"

if [ -n "$AGREEMENT1_DATA" ]; then
    A1_FOUND="true"
    # Parse tab-separated values. Note: Content is last and might contain tabs/newlines, so we extract carefully
    A1_ID=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    A1_NAME=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $2}')
    A1_ACTIVE=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    A1_HTML=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    A1_MODE=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]') # 1 = Manual, 0 = Auto
    A1_TEXT=$(echo "$AGREEMENT1_DATA" | awk -F'\t' '{print $6}')
    
    # Fetch full content separately to avoid truncation or parsing issues
    A1_CONTENT=$(magento_query "SELECT content FROM checkout_agreement WHERE agreement_id=$A1_ID" 2>/dev/null)
    
    # Check store assignment
    A1_STORE_COUNT=$(magento_query "SELECT COUNT(*) FROM checkout_agreement_store WHERE agreement_id=$A1_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi

# 3. Check Agreement 2: Privacy Policy
AGREEMENT2_DATA=$(magento_query "SELECT agreement_id, name, is_active, is_html, mode, checkbox_text FROM checkout_agreement WHERE LOWER(name) LIKE '%privacy%' LIMIT 1" 2>/dev/null | tail -1)

A2_FOUND="false"
A2_ID=""
A2_NAME=""
A2_ACTIVE=""
A2_HTML=""
A2_MODE=""
A2_TEXT=""
A2_CONTENT=""
A2_STORE_COUNT="0"

if [ -n "$AGREEMENT2_DATA" ]; then
    A2_FOUND="true"
    A2_ID=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    A2_NAME=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $2}')
    A2_ACTIVE=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    A2_HTML=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    A2_MODE=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    A2_TEXT=$(echo "$AGREEMENT2_DATA" | awk -F'\t' '{print $6}')
    
    A2_CONTENT=$(magento_query "SELECT content FROM checkout_agreement WHERE agreement_id=$A2_ID" 2>/dev/null)
    A2_STORE_COUNT=$(magento_query "SELECT COUNT(*) FROM checkout_agreement_store WHERE agreement_id=$A2_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi

# Escape JSON strings
A1_NAME_ESC=$(echo "$A1_NAME" | sed 's/"/\\"/g' | sed 's/   /\t/g')
A1_TEXT_ESC=$(echo "$A1_TEXT" | sed 's/"/\\"/g' | sed 's/   /\t/g')
A1_CONTENT_ESC=$(echo "$A1_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

A2_NAME_ESC=$(echo "$A2_NAME" | sed 's/"/\\"/g' | sed 's/   /\t/g')
A2_TEXT_ESC=$(echo "$A2_TEXT" | sed 's/"/\\"/g' | sed 's/   /\t/g')
A2_CONTENT_ESC=$(echo "$A2_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

TEMP_JSON=$(mktemp /tmp/checkout_agreements_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "config_enabled": "${CONFIG_VALUE:-0}",
    "agreement1": {
        "found": $A1_FOUND,
        "name": "$A1_NAME_ESC",
        "is_active": "${A1_ACTIVE:-0}",
        "is_html": "${A1_HTML:-0}",
        "mode": "${A1_MODE:-0}",
        "checkbox_text": "$A1_TEXT_ESC",
        "content": "$A1_CONTENT_ESC",
        "store_count": ${A1_STORE_COUNT:-0}
    },
    "agreement2": {
        "found": $A2_FOUND,
        "name": "$A2_NAME_ESC",
        "is_active": "${A2_ACTIVE:-0}",
        "is_html": "${A2_HTML:-0}",
        "mode": "${A2_MODE:-0}",
        "checkbox_text": "$A2_TEXT_ESC",
        "content": "$A2_CONTENT_ESC",
        "store_count": ${A2_STORE_COUNT:-0}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/checkout_agreements_result.json

echo ""
cat /tmp/checkout_agreements_result.json
echo ""
echo "=== Export Complete ==="