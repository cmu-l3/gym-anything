#!/bin/bash
# Export script for Product Attribute Dropdown task

echo "=== Exporting Product Attribute Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_MAX_ID=$(cat /tmp/initial_max_attribute_id 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the attribute exists
# We query by attribute_code 'material_origin'
ATTR_QUERY="SELECT a.attribute_id, a.attribute_code, a.frontend_label, a.frontend_input, a.is_required
            FROM eav_attribute a
            WHERE a.attribute_code='material_origin'
            AND a.entity_type_id=4" # 4 is catalog_product

ATTR_DATA=$(magento_query "$ATTR_QUERY" 2>/dev/null | tail -1)

ATTR_FOUND="false"
ATTR_ID=""
ATTR_CODE=""
ATTR_LABEL=""
ATTR_INPUT=""
ATTR_REQUIRED=""

if [ -n "$ATTR_DATA" ]; then
    ATTR_FOUND="true"
    ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    ATTR_CODE=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    ATTR_LABEL=$(echo "$ATTR_DATA" | awk -F'\t' '{print $3}')
    ATTR_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    ATTR_REQUIRED=$(echo "$ATTR_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
fi

echo "Attribute Found: $ATTR_FOUND (ID: $ATTR_ID)"

# 2. Get Storefront Properties from catalog_eav_attribute
STOREFRONT_PROPS_JSON="{}"
if [ -n "$ATTR_ID" ]; then
    PROPS_QUERY="SELECT is_searchable, is_visible_in_advanced_search, is_comparable, is_filterable, is_filterable_in_search
                 FROM catalog_eav_attribute
                 WHERE attribute_id=$ATTR_ID"
    PROPS_DATA=$(magento_query "$PROPS_QUERY" 2>/dev/null | tail -1)
    
    IS_SEARCHABLE=$(echo "$PROPS_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    IS_VISIBLE_ADV=$(echo "$PROPS_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    IS_COMPARABLE=$(echo "$PROPS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    IS_FILTERABLE=$(echo "$PROPS_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    IS_FILTERABLE_SEARCH=$(echo "$PROPS_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')

    STOREFRONT_PROPS_JSON=$(cat <<EOF
{
    "is_searchable": "$IS_SEARCHABLE",
    "is_visible_in_advanced_search": "$IS_VISIBLE_ADV",
    "is_comparable": "$IS_COMPARABLE",
    "is_filterable": "$IS_FILTERABLE",
    "is_filterable_in_search": "$IS_FILTERABLE_SEARCH"
}
EOF
)
fi

# 3. Get Options
OPTIONS_JSON="[]"
if [ -n "$ATTR_ID" ]; then
    # eav_attribute_option links to eav_attribute_option_value
    # store_id=0 is the admin/default label
    OPT_QUERY="SELECT v.value 
               FROM eav_attribute_option o
               JOIN eav_attribute_option_value v ON o.option_id = v.option_id
               WHERE o.attribute_id=$ATTR_ID AND v.store_id=0"
    
    # Read lines into a python script to format as JSON array safely
    OPTIONS_RAW=$(magento_query "$OPT_QUERY" 2>/dev/null)
    
    # Use python to convert newline separated list to json list
    OPTIONS_JSON=$(echo "$OPTIONS_RAW" | python3 -c 'import sys, json; lines = [l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))')
fi

# 4. Check Assignment to Default Attribute Set
IS_ASSIGNED="false"
if [ -n "$ATTR_ID" ]; then
    # 4 is catalog_product entity type
    # We find the "Default" set ID first (usually 4, but safe to query)
    DEFAULT_SET_ID=$(magento_query "SELECT attribute_set_id FROM eav_attribute_set WHERE attribute_set_name='Default' AND entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]')
    
    if [ -n "$DEFAULT_SET_ID" ]; then
        ASSIGN_CHECK=$(magento_query "SELECT COUNT(*) FROM eav_entity_attribute WHERE attribute_id=$ATTR_ID AND attribute_set_id=$DEFAULT_SET_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        if [ "$ASSIGN_CHECK" -gt "0" ]; then
            IS_ASSIGNED="true"
        fi
    fi
fi

# Check if it was newly created
NEWLY_CREATED="false"
if [ -n "$ATTR_ID" ] && [ "$ATTR_ID" -gt "$INITIAL_MAX_ID" ]; then
    NEWLY_CREATED="true"
fi
# Fallback: if INITIAL_MAX_ID was 0 or failed, assume created if found
if [ "$INITIAL_MAX_ID" = "0" ] && [ "$ATTR_FOUND" = "true" ]; then
    NEWLY_CREATED="true"
fi

# Escape label for JSON
ATTR_LABEL_ESC=$(echo "$ATTR_LABEL" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/attr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "attribute_found": $ATTR_FOUND,
    "newly_created": $NEWLY_CREATED,
    "attribute_id": "${ATTR_ID:-}",
    "attribute_code": "${ATTR_CODE:-}",
    "frontend_label": "$ATTR_LABEL_ESC",
    "frontend_input": "${ATTR_INPUT:-}",
    "is_required": "${ATTR_REQUIRED:-}",
    "storefront_properties": $STOREFRONT_PROPS_JSON,
    "options": $OPTIONS_JSON,
    "is_assigned_to_default_set": $IS_ASSIGNED,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/product_attribute_result.json

echo ""
cat /tmp/product_attribute_result.json
echo ""
echo "=== Export Complete ==="