#!/bin/bash
# Export script for Cart Price Rule task

echo "=== Exporting Cart Price Rule Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")
GENERAL_GROUP_ID=$(cat /tmp/general_group_id 2>/dev/null | tr -d '[:space:]' || echo "1")

CURRENT_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Find the rule by name (case-insensitive)
RULE_DATA=$(magento_query "SELECT rule_id, name, simple_action, discount_amount, uses_per_coupon, uses_per_customer, coupon_type, use_auto_generation, to_date FROM salesrule WHERE LOWER(TRIM(name))='back2school25' ORDER BY rule_id DESC LIMIT 1" 2>/dev/null | tail -1)

RULE_ID=$(echo "$RULE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RULE_NAME=$(echo "$RULE_DATA" | awk -F'\t' '{print $2}')
DISCOUNT_TYPE=$(echo "$RULE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
DISCOUNT_AMOUNT=$(echo "$RULE_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
USES_PER_COUPON=$(echo "$RULE_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
USES_PER_CUSTOMER=$(echo "$RULE_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
COUPON_TYPE=$(echo "$RULE_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
USE_AUTO_GEN=$(echo "$RULE_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')
TO_DATE=$(echo "$RULE_DATA" | awk -F'\t' '{print $9}' | tr -d '[:space:]')

RULE_FOUND="false"
[ -n "$RULE_ID" ] && RULE_FOUND="true"
echo "Rule found: $RULE_FOUND (ID=$RULE_ID)"
echo "  discount_type=$DISCOUNT_TYPE amount=$DISCOUNT_AMOUNT uses_per_coupon=$USES_PER_COUPON uses_per_customer=$USES_PER_CUSTOMER"

# Check conditions for minimum subtotal (stored in conditions_serialized JSON)
HAS_SUBTOTAL_CONDITION="false"
SUBTOTAL_CONDITION_VALUE=""
if [ -n "$RULE_ID" ]; then
    CONDITIONS_RAW=$(magento_query "SELECT conditions_serialized FROM salesrule WHERE rule_id=$RULE_ID" 2>/dev/null | tail -1 || echo "")
    # Check if conditions blob contains base_subtotal
    if echo "$CONDITIONS_RAW" | grep -qi "base_subtotal"; then
        HAS_SUBTOTAL_CONDITION="true"
        # Extract value near base_subtotal (look for the numeric value "75")
        if echo "$CONDITIONS_RAW" | grep -qi '"75"\|"75.0"\|value.*75'; then
            SUBTOTAL_CONDITION_VALUE="75"
        fi
    fi
fi
echo "Subtotal condition: has=$HAS_SUBTOTAL_CONDITION value=$SUBTOTAL_CONDITION_VALUE"

# Check customer group assignment (General = group_id 1 typically)
GROUP_COUNT="0"
GENERAL_ASSIGNED="false"
NON_GENERAL_ASSIGNED="false"
if [ -n "$RULE_ID" ]; then
    GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule_customer_group WHERE rule_id=$RULE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    GEN_CHECK=$(magento_query "SELECT COUNT(*) FROM salesrule_customer_group WHERE rule_id=$RULE_ID AND customer_group_id=$GENERAL_GROUP_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    [ "${GEN_CHECK:-0}" -gt "0" ] 2>/dev/null && GENERAL_ASSIGNED="true"
    # Check if wholesale (group_id=2) or retailer group is also assigned
    NON_GEN_CHECK=$(magento_query "SELECT COUNT(*) FROM salesrule_customer_group WHERE rule_id=$RULE_ID AND customer_group_id NOT IN ($GENERAL_GROUP_ID)" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    [ "${NON_GEN_CHECK:-0}" -gt "0" ] 2>/dev/null && NON_GENERAL_ASSIGNED="true"
fi
echo "Customer groups: count=$GROUP_COUNT general=$GENERAL_ASSIGNED non_general=$NON_GENERAL_ASSIGNED"

# Count coupon codes with prefix B2S
COUPON_TOTAL="0"
B2S_COUPON_COUNT="0"
if [ -n "$RULE_ID" ]; then
    COUPON_TOTAL=$(magento_query "SELECT COUNT(*) FROM salesrule_coupon WHERE rule_id=$RULE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    B2S_COUPON_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule_coupon WHERE rule_id=$RULE_ID AND LOWER(code) LIKE 'b2s%'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
fi
echo "Coupons: total=$COUPON_TOTAL b2s_prefixed=$B2S_COUPON_COUNT"

# Escape for JSON
RULE_NAME_ESC=$(echo "$RULE_NAME" | sed 's/"/\\"/g')
TO_DATE_ESC=$(echo "$TO_DATE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/cart_price_rule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_rule_count": ${INITIAL_RULE_COUNT:-0},
    "current_rule_count": ${CURRENT_RULE_COUNT:-0},
    "initial_coupon_count": ${INITIAL_COUPON_COUNT:-0},
    "rule_found": $RULE_FOUND,
    "rule_id": "${RULE_ID:-}",
    "rule_name": "$RULE_NAME_ESC",
    "discount_type": "${DISCOUNT_TYPE:-}",
    "discount_amount": "${DISCOUNT_AMOUNT:-}",
    "uses_per_coupon": "${USES_PER_COUPON:-}",
    "uses_per_customer": "${USES_PER_CUSTOMER:-}",
    "coupon_type": "${COUPON_TYPE:-}",
    "use_auto_generation": "${USE_AUTO_GEN:-}",
    "to_date": "$TO_DATE_ESC",
    "has_subtotal_condition": $HAS_SUBTOTAL_CONDITION,
    "subtotal_condition_value": "${SUBTOTAL_CONDITION_VALUE:-}",
    "customer_group_count": ${GROUP_COUNT:-0},
    "general_group_assigned": $GENERAL_ASSIGNED,
    "non_general_group_assigned": $NON_GENERAL_ASSIGNED,
    "coupon_total": ${COUPON_TOTAL:-0},
    "b2s_coupon_count": ${B2S_COUPON_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/cart_price_rule_result.json
echo ""
cat /tmp/cart_price_rule_result.json
echo ""
echo "=== Export Complete ==="
