#!/bin/bash
# Export script for BOGO Promotion Setup task

echo "=== Exporting BOGO Promotion Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Clothing Category ID (for verifying conditions)
CLOTHING_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar WHERE value='Clothing' AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3) LIMIT 1" 2>/dev/null)
echo "Clothing Category ID: $CLOTHING_CAT_ID"

# 2. Query the rule details
echo "Querying rule 'Clothing BOGO'..."
# Fetch specific columns: rule_id, name, simple_action, discount_amount, discount_step, stop_rules_processing, is_active, coupon_type
RULE_DATA=$(magento_query "SELECT rule_id, name, simple_action, discount_amount, discount_step, stop_rules_processing, is_active, coupon_type FROM salesrule WHERE name='Clothing BOGO' ORDER BY rule_id DESC LIMIT 1" 2>/dev/null)

RULE_FOUND="false"
RULE_ID=""
RULE_NAME=""
ACTION=""
AMOUNT=""
STEP=""
STOP_PROCESS=""
IS_ACTIVE=""
COUPON_TYPE=""
CONDITIONS_SERIALIZED=""

if [ -n "$RULE_DATA" ]; then
    RULE_FOUND="true"
    RULE_ID=$(echo "$RULE_DATA" | cut -f1)
    RULE_NAME=$(echo "$RULE_DATA" | cut -f2)
    ACTION=$(echo "$RULE_DATA" | cut -f3)
    AMOUNT=$(echo "$RULE_DATA" | cut -f4)
    STEP=$(echo "$RULE_DATA" | cut -f5)
    STOP_PROCESS=$(echo "$RULE_DATA" | cut -f6)
    IS_ACTIVE=$(echo "$RULE_DATA" | cut -f7)
    COUPON_TYPE=$(echo "$RULE_DATA" | cut -f8)

    # Get conditions serialized separately to avoid parsing issues with large text
    CONDITIONS_SERIALIZED=$(magento_query "SELECT conditions_serialized FROM salesrule WHERE rule_id=$RULE_ID" 2>/dev/null)
    
    echo "Rule found: ID=$RULE_ID, Action=$ACTION, Step=$STEP, Amount=$AMOUNT"
else
    echo "Rule 'Clothing BOGO' NOT found"
fi

# 3. Check if Clothing Category ID is present in conditions
CATEGORY_CONDITION_MET="false"
if [ -n "$CONDITIONS_SERIALIZED" ] && [ -n "$CLOTHING_CAT_ID" ]; then
    # We look for the Category ID in the serialized string. 
    # It usually appears like "value": "ID" or "value":"ID" or inside an array.
    # Simple grep is usually sufficient for checking presence.
    if echo "$CONDITIONS_SERIALIZED" | grep -q "$CLOTHING_CAT_ID"; then
        CATEGORY_CONDITION_MET="true"
    fi
fi

# Escape strings for JSON
RULE_NAME_ESC=$(echo "$RULE_NAME" | sed 's/"/\\"/g')
# Action might be empty if not set
ACTION=${ACTION:-""}

# Create JSON result
TEMP_JSON=$(mktemp /tmp/bogo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rule_found": $RULE_FOUND,
    "rule": {
        "id": "$RULE_ID",
        "name": "$RULE_NAME_ESC",
        "simple_action": "$ACTION",
        "discount_amount": "$AMOUNT",
        "discount_step": "$STEP",
        "stop_rules_processing": "$STOP_PROCESS",
        "is_active": "$IS_ACTIVE",
        "coupon_type": "$COUPON_TYPE",
        "clothing_category_id": "$CLOTHING_CAT_ID",
        "category_condition_met": $CATEGORY_CONDITION_MET
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/bogo_result.json

echo ""
cat /tmp/bogo_result.json
echo ""
echo "=== Export Complete ==="