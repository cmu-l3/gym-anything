#!/bin/bash
# Export script for Wine Layered Navigation task

echo "=== Exporting Wine Layered Navigation Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Load initial counts
INITIAL_ATTR_COUNT=$(cat /tmp/initial_attr_count 2>/dev/null || echo "0")

# 1. Get Attribute Definitions and Properties
# We need to join eav_attribute (base) with catalog_eav_attribute (storefront props)
# Codes: wine_region, wine_varietal, wine_vintage
echo "Querying attribute properties..."
ATTR_PROPS=$(magento_query_headers "
SELECT ea.attribute_code, ea.frontend_input, ea.frontend_label,
       cea.is_filterable, cea.is_visible_on_front, cea.used_in_product_listing, cea.is_searchable
FROM eav_attribute ea
JOIN catalog_eav_attribute cea ON ea.attribute_id = cea.attribute_id
WHERE ea.attribute_code IN ('wine_region', 'wine_varietal', 'wine_vintage')
AND ea.entity_type_id = 4
")

# 2. Get Attribute Options
echo "Querying attribute options..."
ATTR_OPTIONS=$(magento_query_headers "
SELECT ea.attribute_code, v.value
FROM eav_attribute ea
JOIN eav_attribute_option o ON ea.attribute_id = o.attribute_id
JOIN eav_attribute_option_value v ON o.option_id = v.option_id
WHERE ea.attribute_code IN ('wine_region', 'wine_varietal', 'wine_vintage')
AND ea.entity_type_id = 4
AND v.store_id = 0
ORDER BY ea.attribute_code, v.value
")

# 3. Get Attribute Group Assignments in Default Set
echo "Querying attribute group assignments..."
ATTR_GROUPS=$(magento_query_headers "
SELECT ea.attribute_code, ag.attribute_group_name
FROM eav_attribute ea
JOIN eav_entity_attribute eea ON ea.attribute_id = eea.attribute_id
JOIN eav_attribute_group ag ON eea.attribute_group_id = ag.attribute_group_id
JOIN eav_attribute_set eas ON ag.attribute_set_id = eas.attribute_set_id
WHERE ea.attribute_code IN ('wine_region', 'wine_varietal', 'wine_vintage')
AND eas.attribute_set_name = 'Default'
AND eas.entity_type_id = 4
")

# Calculate current counts
CURRENT_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Prepare JSON
# Python script to parse the tab-separated SQL output into structured JSON
python3 << EOF
import json
import sys

def parse_sql_output(raw_output):
    lines = raw_output.strip().split('\n')
    if not lines: return []
    headers = lines[0].split('\t')
    results = []
    for line in lines[1:]:
        values = line.split('\t')
        if len(values) == len(headers):
            results.append(dict(zip(headers, values)))
    return results

props_raw = """$ATTR_PROPS"""
options_raw = """$ATTR_OPTIONS"""
groups_raw = """$ATTR_GROUPS"""

props = parse_sql_output(props_raw)
options = parse_sql_output(options_raw)
groups = parse_sql_output(groups_raw)

# Restructure data
attributes = {}
for p in props:
    code = p['attribute_code']
    attributes[code] = {
        'exists': True,
        'frontend_input': p['frontend_input'],
        'is_filterable': p['is_filterable'],
        'is_visible_on_front': p['is_visible_on_front'],
        'used_in_product_listing': p['used_in_product_listing'],
        'is_searchable': p['is_searchable'],
        'options': [],
        'group': None
    }

for o in options:
    code = o['attribute_code']
    if code in attributes:
        attributes[code]['options'].append(o['value'])

for g in groups:
    code = g['attribute_code']
    if code in attributes:
        attributes[code]['group'] = g['attribute_group_name']

result = {
    "initial_attr_count": int("${INITIAL_ATTR_COUNT:-0}"),
    "current_attr_count": int("${CURRENT_ATTR_COUNT:-0}"),
    "attributes": attributes,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/wine_attributes_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("JSON generation complete")
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/wine_attributes_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="