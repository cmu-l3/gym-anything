#!/bin/bash
# Export script for Jewelry Attribute Set task

echo "=== Exporting Jewelry Attribute Set Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_ATTR_COUNT=$(cat /tmp/initial_attr_count 2>/dev/null || echo "0")
INITIAL_SET_COUNT=$(cat /tmp/initial_set_count 2>/dev/null || echo "0")

CURRENT_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
CURRENT_SET_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute_set WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# 1. Check Attribute: jewelry_material
echo "Checking jewelry_material..."
MAT_DATA=$(magento_query "SELECT attribute_id, frontend_input, is_user_defined FROM eav_attribute WHERE attribute_code='jewelry_material' AND entity_type_id=4" 2>/dev/null | tail -1)
MAT_ID=$(echo "$MAT_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
MAT_INPUT=$(echo "$MAT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
MAT_FOUND="false"
[ -n "$MAT_ID" ] && MAT_FOUND="true"

MAT_OPTIONS=""
if [ "$MAT_FOUND" = "true" ]; then
    # Get options (joined with option_value)
    MAT_OPTIONS=$(magento_query "SELECT v.value FROM eav_attribute_option o JOIN eav_attribute_option_value v ON o.option_id=v.option_id WHERE o.attribute_id=$MAT_ID AND v.store_id=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# 2. Check Attribute: gemstone_type
echo "Checking gemstone_type..."
GEM_DATA=$(magento_query "SELECT attribute_id, frontend_input FROM eav_attribute WHERE attribute_code='gemstone_type' AND entity_type_id=4" 2>/dev/null | tail -1)
GEM_ID=$(echo "$GEM_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
GEM_INPUT=$(echo "$GEM_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
GEM_FOUND="false"
[ -n "$GEM_ID" ] && GEM_FOUND="true"

GEM_OPTIONS=""
if [ "$GEM_FOUND" = "true" ]; then
    GEM_OPTIONS=$(magento_query "SELECT v.value FROM eav_attribute_option o JOIN eav_attribute_option_value v ON o.option_id=v.option_id WHERE o.attribute_id=$GEM_ID AND v.store_id=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# 3. Check Attribute: chain_length_inches
echo "Checking chain_length_inches..."
CHAIN_DATA=$(magento_query "SELECT attribute_id, frontend_input FROM eav_attribute WHERE attribute_code='chain_length_inches' AND entity_type_id=4" 2>/dev/null | tail -1)
CHAIN_ID=$(echo "$CHAIN_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CHAIN_INPUT=$(echo "$CHAIN_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
CHAIN_FOUND="false"
[ -n "$CHAIN_ID" ] && CHAIN_FOUND="true"

# 4. Check Attribute Set: Jewelry
echo "Checking Attribute Set 'Jewelry'..."
SET_DATA=$(magento_query "SELECT attribute_set_id, attribute_set_name FROM eav_attribute_set WHERE LOWER(TRIM(attribute_set_name))='jewelry' AND entity_type_id=4" 2>/dev/null | tail -1)
SET_ID=$(echo "$SET_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
SET_NAME=$(echo "$SET_DATA" | awk -F'\t' '{print $2}')
SET_FOUND="false"
[ -n "$SET_ID" ] && SET_FOUND="true"

# 5. Check Attribute Group: Jewelry Specifications
echo "Checking Attribute Group..."
GROUP_FOUND="false"
GROUP_ID=""
if [ "$SET_FOUND" = "true" ]; then
    GROUP_DATA=$(magento_query "SELECT attribute_group_id, attribute_group_name FROM eav_attribute_group WHERE attribute_set_id=$SET_ID AND LOWER(TRIM(attribute_group_name))='jewelry specifications'" 2>/dev/null | tail -1)
    GROUP_ID=$(echo "$GROUP_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    [ -n "$GROUP_ID" ] && GROUP_FOUND="true"
fi

# 6. Check Assignments (Attributes assigned to Set/Group)
echo "Checking assignments..."
MAT_ASSIGNED="false"
GEM_ASSIGNED="false"
CHAIN_ASSIGNED="false"

if [ "$GROUP_FOUND" = "true" ] && [ -n "$MAT_ID" ]; then
    RES=$(magento_query "SELECT COUNT(*) FROM eav_entity_attribute WHERE attribute_set_id=$SET_ID AND attribute_group_id=$GROUP_ID AND attribute_id=$MAT_ID" 2>/dev/null | tail -1)
    [ "$RES" -gt 0 ] && MAT_ASSIGNED="true"
fi
if [ "$GROUP_FOUND" = "true" ] && [ -n "$GEM_ID" ]; then
    RES=$(magento_query "SELECT COUNT(*) FROM eav_entity_attribute WHERE attribute_set_id=$SET_ID AND attribute_group_id=$GROUP_ID AND attribute_id=$GEM_ID" 2>/dev/null | tail -1)
    [ "$RES" -gt 0 ] && GEM_ASSIGNED="true"
fi
if [ "$GROUP_FOUND" = "true" ] && [ -n "$CHAIN_ID" ]; then
    RES=$(magento_query "SELECT COUNT(*) FROM eav_entity_attribute WHERE attribute_set_id=$SET_ID AND attribute_group_id=$GROUP_ID AND attribute_id=$CHAIN_ID" 2>/dev/null | tail -1)
    [ "$RES" -gt 0 ] && CHAIN_ASSIGNED="true"
fi

# Create JSON
TEMP_JSON=$(mktemp /tmp/jewelry_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_attr_count": ${INITIAL_ATTR_COUNT:-0},
    "current_attr_count": ${CURRENT_ATTR_COUNT:-0},
    "initial_set_count": ${INITIAL_SET_COUNT:-0},
    "current_set_count": ${CURRENT_SET_COUNT:-0},
    "jewelry_material": {
        "found": $MAT_FOUND,
        "input": "${MAT_INPUT:-}",
        "options": "${MAT_OPTIONS:-}"
    },
    "gemstone_type": {
        "found": $GEM_FOUND,
        "input": "${GEM_INPUT:-}",
        "options": "${GEM_OPTIONS:-}"
    },
    "chain_length_inches": {
        "found": $CHAIN_FOUND,
        "input": "${CHAIN_INPUT:-}"
    },
    "attribute_set": {
        "found": $SET_FOUND,
        "id": "${SET_ID:-}",
        "name": "${SET_NAME:-}"
    },
    "attribute_group": {
        "found": $GROUP_FOUND,
        "id": "${GROUP_ID:-}"
    },
    "assignments": {
        "jewelry_material": $MAT_ASSIGNED,
        "gemstone_type": $GEM_ASSIGNED,
        "chain_length_inches": $CHAIN_ASSIGNED
    }
}
EOF

# Safe move
safe_write_json "$TEMP_JSON" /tmp/jewelry_result.json
echo ""
cat /tmp/jewelry_result.json
echo ""
echo "=== Export Complete ==="