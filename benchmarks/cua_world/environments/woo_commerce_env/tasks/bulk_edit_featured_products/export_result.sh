#!/bin/bash
# Export script for Bulk Edit Featured Products task

echo "=== Exporting Bulk Edit Featured Products Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Current Featured Products
# We need to know WHICH products are featured to verify specific SKUs
echo "Querying featured products..."

QUERY="SELECT p.ID, p.post_title, pm.meta_value as sku
FROM wp_posts p
JOIN wp_term_relationships tr ON p.ID = tr.object_id
JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
JOIN wp_terms t ON tt.term_id = t.term_id
LEFT JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
WHERE p.post_type = 'product'
AND p.post_status = 'publish'
AND tt.taxonomy = 'product_visibility'
AND t.slug = 'featured'"

# Execute query
FEATURED_LIST=$(wc_query "$QUERY")
FEATURED_COUNT=$(echo "$FEATURED_LIST" | grep -v "^$" | wc -l)

echo "Found $FEATURED_COUNT featured products."
echo "$FEATURED_LIST"

# 4. Check for Specific SKUs in the result
# WBH-001 (Headphones)
HAS_WBH=$(echo "$FEATURED_LIST" | grep -i "WBH-001" > /dev/null && echo "true" || echo "false")
# OCT-BLK-M (T-Shirt)
HAS_OCT=$(echo "$FEATURED_LIST" | grep -i "OCT-BLK-M" > /dev/null && echo "true" || echo "false")
# MWS-GRY-L (Sweater)
HAS_MWS=$(echo "$FEATURED_LIST" | grep -i "MWS-GRY-L" > /dev/null && echo "true" || echo "false")

# 5. Check if WordPress/Browser was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/bulk_edit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "initial_featured_count": $(cat /tmp/initial_featured_count 2>/dev/null || echo "0"),
    "final_featured_count": $FEATURED_COUNT,
    "target_status": {
        "WBH-001": $HAS_WBH,
        "OCT-BLK-M": $HAS_OCT,
        "MWS-GRY-L": $HAS_MWS
    },
    "featured_products_list": "$(echo "$FEATURED_LIST" | tr '\n' ';' | sed 's/"/\\"/g')"
}
EOF

# Move to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="