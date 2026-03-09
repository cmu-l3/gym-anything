#!/bin/bash
# Export script for Catalog Price Rule task

echo "=== Exporting Catalog Price Rule Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
ELECTRONICS_ID=$(cat /tmp/electronics_category_id 2>/dev/null || echo "0")

CURRENT_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalogrule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Find the rule by name (case-insensitive)
# We select pertinent fields to verify configuration
RULE_DATA=$(magento_query "SELECT rule_id, name, simple_action, discount_amount, from_date, to_date, sort_order, stop_rules_processing, is_active, conditions_serialized FROM catalogrule WHERE LOWER(TRIM(name))='summer_clearance_2025' ORDER BY rule_id DESC LIMIT 1" 2>/dev/null | tail -1)

# Initialize variables
RULE_FOUND="false"
RULE_ID=""
RULE_NAME=""
SIMPLE_ACTION=""
DISCOUNT_AMOUNT=""
FROM_DATE=""
TO_DATE=""
SORT_ORDER=""
STOP_PROCESSING=""
IS_ACTIVE=""
CONDITIONS=""
APPLIED_PRODUCT_COUNT="0"
CUSTOMER_GROUPS_JSON="[]"
HAS_ELECTRONICS_CONDITION="false"

if [ -n "$RULE_DATA" ]; then
    RULE_FOUND="true"
    
    # Parse tab-separated values. Note: conditions_serialized is the last column and might contain tabs or special chars, 
    # but magento_query output is -B (batch) tab separated. 
    # Since conditions_serialized is JSON, we should be careful. 
    # Simpler approach: extract ID first, then query other fields individually if needed for safety.
    
    RULE_ID=$(echo "$RULE_DATA" | awk -F'\t' '{print $1}')
    
    # Re-query specific fields safely by ID to avoid parsing issues with the serialized blob in awk
    RULE_NAME=$(magento_query "SELECT name FROM catalogrule WHERE rule_id=$RULE_ID")
    SIMPLE_ACTION=$(magento_query "SELECT simple_action FROM catalogrule WHERE rule_id=$RULE_ID")
    DISCOUNT_AMOUNT=$(magento_query "SELECT discount_amount FROM catalogrule WHERE rule_id=$RULE_ID")
    FROM_DATE=$(magento_query "SELECT from_date FROM catalogrule WHERE rule_id=$RULE_ID")
    TO_DATE=$(magento_query "SELECT to_date FROM catalogrule WHERE rule_id=$RULE_ID")
    SORT_ORDER=$(magento_query "SELECT sort_order FROM catalogrule WHERE rule_id=$RULE_ID")
    STOP_PROCESSING=$(magento_query "SELECT stop_rules_processing FROM catalogrule WHERE rule_id=$RULE_ID")
    IS_ACTIVE=$(magento_query "SELECT is_active FROM catalogrule WHERE rule_id=$RULE_ID")
    CONDITIONS=$(magento_query "SELECT conditions_serialized FROM catalogrule WHERE rule_id=$RULE_ID")

    # Check if rule was applied (indexed)
    APPLIED_PRODUCT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalogrule_product WHERE rule_id=$RULE_ID" 2>/dev/null | tail -1)

    # Get customer groups
    # Group 0 = NOT LOGGED IN, 1 = General, 2 = Wholesale, 3 = Retailer
    CUSTOMER_GROUPS=$(magento_query "SELECT customer_group_id FROM catalogrule_customer_group WHERE rule_id=$RULE_ID" 2>/dev/null)
    # Convert newline separated list to JSON array
    CUSTOMER_GROUPS_JSON=$(echo "$CUSTOMER_GROUPS" | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')

    # Check conditions for Electronics Category
    # We look for the Category ID in the serialized conditions string
    # Pattern usually involves "attribute":"category_ids","operator":"==","value":"3" (or whatever ID is)
    # or "value":[..., "3", ...] if multi-select
    if [ -n "$ELECTRONICS_ID" ] && [ "$ELECTRONICS_ID" != "0" ]; then
        if echo "$CONDITIONS" | grep -q "$ELECTRONICS_ID"; then
             # A simple grep isn't perfect but strong indicator if combined with "category_ids"
             if echo "$CONDITIONS" | grep -q "category_ids"; then
                 HAS_ELECTRONICS_CONDITION="true"
             fi
        fi
    fi
fi

# Sanitize strings for JSON
RULE_NAME_ESC=$(echo "$RULE_NAME" | sed 's/"/\\"/g')
CONDITIONS_ESC=$(echo "$CONDITIONS" | jq -R '.')

TEMP_JSON=$(mktemp /tmp/catalog_rule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_rule_count": ${INITIAL_RULE_COUNT:-0},
    "current_rule_count": ${CURRENT_RULE_COUNT:-0},
    "electronics_category_id": "${ELECTRONICS_ID:-0}",
    "rule_found": $RULE_FOUND,
    "rule_id": "${RULE_ID:-}",
    "rule_name": "$RULE_NAME_ESC",
    "simple_action": "${SIMPLE_ACTION:-}",
    "discount_amount": "${DISCOUNT_AMOUNT:-}",
    "from_date": "${FROM_DATE:-}",
    "to_date": "${TO_DATE:-}",
    "sort_order": "${SORT_ORDER:-}",
    "stop_rules_processing": "${STOP_PROCESSING:-}",
    "is_active": "${IS_ACTIVE:-}",
    "customer_groups": $CUSTOMER_GROUPS_JSON,
    "applied_product_count": ${APPLIED_PRODUCT_COUNT:-0},
    "has_electronics_condition": $HAS_ELECTRONICS_CONDITION
}
EOF

safe_write_json "$TEMP_JSON" /tmp/catalog_rule_result.json

echo ""
cat /tmp/catalog_rule_result.json
echo ""
echo "=== Export Complete ==="