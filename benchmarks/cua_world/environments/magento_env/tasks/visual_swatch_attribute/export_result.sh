#!/bin/bash
# Export script for Visual Swatch Attribute task

echo "=== Exporting Visual Swatch Attribute Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get attribute counts
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_attribute_count 2>/dev/null || echo "0")

echo "Attribute count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# 1. Find the attribute
echo "Searching for attribute 'finish_color'..."
ATTR_DATA=$(magento_query "SELECT attribute_id, attribute_code, frontend_input FROM eav_attribute WHERE attribute_code='finish_color' AND entity_type_id=4" 2>/dev/null | tail -1)

ATTR_FOUND="false"
ATTR_ID=""
ATTR_CODE=""
FRONTEND_Input=""

if [ -n "$ATTR_DATA" ]; then
    ATTR_FOUND="true"
    ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    ATTR_CODE=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}')
    FRONTEND_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $3}')
fi

echo "Attribute found: $ATTR_FOUND (ID: $ATTR_ID, Input: $FRONTEND_INPUT)"

# 2. Get Layered Navigation Properties (from catalog_eav_attribute)
IS_FILTERABLE="0"
IS_VISIBLE_ON_FRONT="0"
IS_SEARCHABLE="0"

if [ "$ATTR_FOUND" = "true" ]; then
    PROPS=$(magento_query "SELECT is_filterable, is_visible_on_front, is_searchable FROM catalog_eav_attribute WHERE attribute_id=$ATTR_ID" 2>/dev/null | tail -1)
    IS_FILTERABLE=$(echo "$PROPS" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    IS_VISIBLE_ON_FRONT=$(echo "$PROPS" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    IS_SEARCHABLE=$(echo "$PROPS" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# 3. Get Options and Swatches
# We need to construct a JSON array of options manually because bash/mysql interaction is tricky for nested data
OPTIONS_JSON="[]"

if [ "$ATTR_FOUND" = "true" ]; then
    # Create temporary file for options data
    # Query returns: option_id | label | swatch_value (hex)
    # We join eav_attribute_option -> eav_attribute_option_value -> eav_attribute_option_swatch
    # We use store_id = 0 for default admin values
    
    magento_query "SELECT o.option_id, v.value, s.value 
                   FROM eav_attribute_option o 
                   LEFT JOIN eav_attribute_option_value v ON o.option_id = v.option_id 
                   LEFT JOIN eav_attribute_option_swatch s ON o.option_id = s.option_id 
                   WHERE o.attribute_id = $ATTR_ID 
                   AND v.store_id = 0 
                   AND (s.store_id = 0 OR s.store_id IS NULL)
                   AND (s.type = 1 OR s.type IS NULL)" > /tmp/attr_options.txt 2>/dev/null

    # Parse the output into a JSON array
    # Python is safer for JSON construction
    OPTIONS_JSON=$(python3 << 'PYEOF'
import json
import sys

options = []
try:
    with open('/tmp/attr_options.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                opt_id = parts[0]
                label = parts[1]
                hex_val = parts[2] if len(parts) > 2 else ""
                # Swatch values in DB often don't have '#', add if missing for consistency
                if hex_val and not hex_val.startswith('#'):
                    hex_val = '#' + hex_val
                
                options.append({
                    "id": opt_id,
                    "label": label,
                    "hex": hex_val
                })
except Exception as e:
    pass

print(json.dumps(options))
PYEOF
)
fi

echo "Options found: $OPTIONS_JSON"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/visual_swatch_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "attribute_found": $ATTR_FOUND,
    "attribute_id": "${ATTR_ID:-}",
    "attribute_code": "${ATTR_CODE:-}",
    "frontend_input": "${FRONTEND_INPUT:-}",
    "is_filterable": "${IS_FILTERABLE:-0}",
    "is_visible_on_front": "${IS_VISIBLE_ON_FRONT:-0}",
    "is_searchable": "${IS_SEARCHABLE:-0}",
    "options": $OPTIONS_JSON,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/visual_swatch_result.json

echo ""
cat /tmp/visual_swatch_result.json
echo ""
echo "=== Export Complete ==="