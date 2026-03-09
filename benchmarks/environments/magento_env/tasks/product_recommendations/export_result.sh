#!/bin/bash
# Export script for Product Recommendations task

echo "=== Exporting Product Recommendations Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TARGET_SKU="PHONE-001"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get target product ID
TARGET_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

# Check if product exists
PRODUCT_FOUND="false"
if [ -n "$TARGET_ID" ] && [ "$TARGET_ID" != "0" ]; then
    PRODUCT_FOUND="true"
fi

# Query all links for this product
# Join with entity table to get SKUs of linked products
# link_type_id: 1=related, 4=upsell, 5=crosssell
echo "Querying product links..."

# We use a custom query to construct a JSON array directly from SQL if possible, 
# or simpler: dump TSV and process in Python verifier, OR dump to a temp file and convert here.
# Let's dump to a TSV file that we can easily parse into JSON.

LINKS_TSV=$(magento_query "SELECT l.link_type_id, e.sku 
FROM catalog_product_link l 
JOIN catalog_product_entity e ON l.linked_product_id = e.entity_id 
WHERE l.product_id=$TARGET_ID")

echo "--- Raw Links Data ---"
echo "$LINKS_TSV"
echo "----------------------"

# Convert TSV to JSON array manually
# Format: [{"type_id": "1", "sku": "SKU1"}, ...]
JSON_LINKS="["
FIRST="true"

# Read line by line
while IFS=$'\t' read -r TYPE_ID SKU; do
    if [ -z "$TYPE_ID" ]; then continue; fi
    
    if [ "$FIRST" = "true" ]; then
        FIRST="false"
    else
        JSON_LINKS="$JSON_LINKS,"
    fi
    
    JSON_LINKS="$JSON_LINKS {\"type_id\": \"$TYPE_ID\", \"sku\": \"$SKU\"}"
done <<< "$LINKS_TSV"

JSON_LINKS="$JSON_LINKS]"

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_link_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_link WHERE product_id=$TARGET_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Counts: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/prod_recs_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_sku": "$TARGET_SKU",
    "product_found": $PRODUCT_FOUND,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "links": $JSON_LINKS,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/prod_recs_result.json

echo ""
cat /tmp/prod_recs_result.json
echo ""
echo "=== Export Complete ==="