#!/bin/bash
# Export script for Customer Attribute task

echo "=== Exporting Customer Attribute Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

CUSTOMER_ENTITY_TYPE_ID=$(cat /tmp/customer_entity_type_id 2>/dev/null | tr -d '[:space:]' || echo "1")
INITIAL_ATTR_COUNT=$(cat /tmp/initial_customer_attr_count 2>/dev/null || echo "0")

# Find the skin_concern attribute
ATTR_DATA=$(magento_query "SELECT attribute_id, attribute_code, frontend_input, is_required, frontend_label FROM eav_attribute WHERE attribute_code='skin_concern' AND entity_type_id=$CUSTOMER_ENTITY_TYPE_ID LIMIT 1" 2>/dev/null | tail -1)

ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ATTR_CODE=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
FRONTEND_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
IS_REQUIRED=$(echo "$ATTR_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
FRONTEND_LABEL=$(echo "$ATTR_DATA" | awk -F'\t' '{print $5}')

ATTR_FOUND="false"
[ -n "$ATTR_ID" ] && ATTR_FOUND="true"
echo "Attribute: ID=$ATTR_ID code=$ATTR_CODE input=$FRONTEND_INPUT required=$IS_REQUIRED found=$ATTR_FOUND"

# Check customer_eav_attribute for storefront visibility and forms
IS_VISIBLE_ON_FRONT="0"
IS_VISIBLE="0"
USED_IN_FORMS=""
if [ -n "$ATTR_ID" ]; then
    CUST_ATTR_DATA=$(magento_query "SELECT is_visible, is_visible_on_front FROM customer_eav_attribute WHERE attribute_id=$ATTR_ID LIMIT 1" 2>/dev/null | tail -1)
    IS_VISIBLE=$(echo "$CUST_ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]' || echo "0")
    IS_VISIBLE_ON_FRONT=$(echo "$CUST_ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]' || echo "0")

    # Check which forms the attribute is used in
    USED_IN_FORMS=$(magento_query "SELECT GROUP_CONCAT(form_code) FROM customer_form_attribute WHERE attribute_id=$ATTR_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "")
fi
echo "Visibility: is_visible=$IS_VISIBLE on_front=$IS_VISIBLE_ON_FRONT forms=$USED_IN_FORMS"

# Count dropdown options
OPTION_COUNT="0"
OPTION_VALUES=""
REQUIRED_OPTIONS_FOUND="0"
if [ -n "$ATTR_ID" ]; then
    OPTION_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute_option WHERE attribute_id=$ATTR_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

    # Get all option values (store_id=0 is admin label)
    OPTION_VALUES=$(magento_query "SELECT GROUP_CONCAT(LOWER(eaov.value) ORDER BY eao.sort_order SEPARATOR '|') FROM eav_attribute_option eao JOIN eav_attribute_option_value eaov ON eao.option_id=eaov.option_id WHERE eao.attribute_id=$ATTR_ID AND eaov.store_id=0" 2>/dev/null | tail -1 | tr -d '\n' || echo "")

    # Check for each required option (case-insensitive substring match)
    REQUIRED_OPTIONS_FOUND=0
    for OPT in "acne" "anti-aging" "hyperpigmentation" "dryness" "sensitivity"; do
        if echo "$OPTION_VALUES" | grep -qi "$OPT"; then
            REQUIRED_OPTIONS_FOUND=$((REQUIRED_OPTIONS_FOUND + 1))
        fi
    done
fi
echo "Options: count=$OPTION_COUNT required_found=$REQUIRED_OPTIONS_FOUND values=$OPTION_VALUES"

# Check if used in registration form
IN_REGISTRATION_FORM="false"
IN_ACCOUNT_EDIT_FORM="false"
if echo "$USED_IN_FORMS" | grep -qi "register\|customer_account_create"; then
    IN_REGISTRATION_FORM="true"
fi
if echo "$USED_IN_FORMS" | grep -qi "account_edit\|customer_account_edit"; then
    IN_ACCOUNT_EDIT_FORM="true"
fi

# Escape for JSON
FRONTEND_LABEL_ESC=$(echo "$FRONTEND_LABEL" | sed 's/"/\\"/g')
OPTION_VALUES_ESC=$(echo "$OPTION_VALUES" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/customer_attribute_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_attr_count": ${INITIAL_ATTR_COUNT:-0},
    "attr_found": $ATTR_FOUND,
    "attribute_id": "${ATTR_ID:-}",
    "attribute_code": "${ATTR_CODE:-}",
    "frontend_input": "${FRONTEND_INPUT:-}",
    "is_required": "${IS_REQUIRED:-0}",
    "frontend_label": "$FRONTEND_LABEL_ESC",
    "is_visible": "${IS_VISIBLE:-0}",
    "is_visible_on_front": "${IS_VISIBLE_ON_FRONT:-0}",
    "used_in_forms": "${USED_IN_FORMS:-}",
    "in_registration_form": $IN_REGISTRATION_FORM,
    "in_account_edit_form": $IN_ACCOUNT_EDIT_FORM,
    "option_count": ${OPTION_COUNT:-0},
    "required_options_found": ${REQUIRED_OPTIONS_FOUND:-0},
    "option_values": "$OPTION_VALUES_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/customer_attribute_result.json
echo ""
cat /tmp/customer_attribute_result.json
echo ""
echo "=== Export Complete ==="
