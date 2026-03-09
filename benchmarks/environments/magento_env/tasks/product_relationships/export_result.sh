#!/bin/bash
# Export script for Product Relationships task

echo "=== Exporting Product Relationships Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

MAIN_SKU="LAPTOP-001"
INITIAL_COUNT=$(cat /tmp/initial_link_count 2>/dev/null || echo "0")

# Get Product ID
MAIN_PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$MAIN_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

echo "Analyzing links for product $MAIN_SKU (ID: $MAIN_PRODUCT_ID)..."

# Get current link count
CURRENT_COUNT="0"
if [ -n "$MAIN_PRODUCT_ID" ]; then
    CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_link WHERE product_id=$MAIN_PRODUCT_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi
echo "Link count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Get details of all links
# We join catalog_product_link (cpl) with catalog_product_entity (cpe) to get linked SKUs
# Link Types: 1=relation (related), 4=up_sell, 5=cross_sell
LINKS_JSON="[]"

if [ -n "$MAIN_PRODUCT_ID" ] && [ "$CURRENT_COUNT" -gt "0" ]; then
    # Helper python script to format SQL output as JSON because bash string manipulation is painful
    cat > /tmp/format_links.py << PYEOF
import sys
import json

lines = sys.stdin.readlines()
links = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 3:
        links.append({
            "linked_sku": parts[0],
            "link_type_id": parts[1],
            "link_type_code": parts[2]
        })
print(json.dumps(links))
PYEOF

    # Execute query
    # Columns: linked_sku, link_type_id, link_type_code
    QUERY="SELECT cpe.sku, cpl.link_type_id, cplt.code 
           FROM catalog_product_link cpl 
           JOIN catalog_product_entity cpe ON cpl.linked_product_id = cpe.entity_id 
           JOIN catalog_product_link_type cplt ON cpl.link_type_id = cplt.link_type_id 
           WHERE cpl.product_id = $MAIN_PRODUCT_ID"
    
    RAW_DATA=$(magento_query "$QUERY" 2>/dev/null)
    
    if [ -n "$RAW_DATA" ]; then
        LINKS_JSON=$(echo "$RAW_DATA" | python3 /tmp/format_links.py)
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/product_relationships_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "main_sku": "$MAIN_SKU",
    "main_product_id": "${MAIN_PRODUCT_ID:-}",
    "initial_link_count": ${INITIAL_COUNT:-0},
    "current_link_count": ${CURRENT_COUNT:-0},
    "links": $LINKS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/product_relationships_result.json

echo ""
cat /tmp/product_relationships_result.json
echo ""
echo "=== Export Complete ==="