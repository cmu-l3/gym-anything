#!/bin/bash
# Export script for Curate Catalog Sorting task

echo "=== Exporting Curate Catalog Sorting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the state of the specific products
# We need the ID, Name, Menu Order, and Modification Date
echo "Querying product states..."

# Helper to get JSON object for a product
get_product_json() {
    local name="$1"
    # Use SQL to fetch details. Note: modifying menu_order updates post_modified
    local query="SELECT ID, menu_order, post_modified FROM wp_posts WHERE post_type='product' AND post_title='$name' LIMIT 1"
    local result=$(wc_query "$query")
    
    if [ -z "$result" ]; then
        echo "null"
    else
        local id=$(echo "$result" | cut -f1)
        local order=$(echo "$result" | cut -f2)
        local mod_time=$(echo "$result" | cut -f3)
        # Convert mod_time to timestamp for easy comparison
        local mod_ts=$(date -d "$mod_time" +%s)
        
        echo "{\"id\": $id, \"menu_order\": $order, \"modified_ts\": $mod_ts}"
    fi
}

SWEATER_JSON=$(get_product_json "Merino Wool Sweater")
JEANS_JSON=$(get_product_json "Slim Fit Denim Jeans")
CONTROL_JSON=$(get_product_json "Organic Cotton T-Shirt")

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/sorting_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "products": {
        "sweater": $SWEATER_JSON,
        "jeans": $JEANS_JSON,
        "control": $CONTROL_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# 5. Safe move to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="