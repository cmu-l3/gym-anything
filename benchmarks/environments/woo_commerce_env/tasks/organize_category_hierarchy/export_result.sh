#!/bin/bash
echo "=== Exporting Organize Category Hierarchy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ==============================================================================
# DATA EXTRACTION
# ==============================================================================

# Helper to get category details JSON object
get_category_json() {
    local name="$1"
    local data
    data=$(get_category_by_name "$name" 2>/dev/null)
    
    if [ -n "$data" ]; then
        local id=$(echo "$data" | cut -f1)
        local slug=$(echo "$data" | cut -f3)
        local parent=$(echo "$data" | cut -f4)
        local count=$(echo "$data" | cut -f5)
        local desc=$(wc_query "SELECT description FROM wp_term_taxonomy WHERE term_id=$id AND taxonomy='product_cat' LIMIT 1")
        # Escape description for JSON
        local desc_esc=$(json_escape "$desc")
        
        echo "{\"exists\": true, \"id\": $id, \"slug\": \"$slug\", \"parent\": $parent, \"count\": $count, \"description\": \"$desc_esc\"}"
    else
        echo "{\"exists\": false}"
    fi
}

# 1. Check Categories
APPAREL_JSON=$(get_category_json "Apparel")
TOPS_JSON=$(get_category_json "Tops")
BOTTOMS_JSON=$(get_category_json "Bottoms")

# 2. Check Product Assignments
check_product_category() {
    local prod_name="$1"
    local target_cat="$2"
    
    # Get product ID
    local prod_data=$(get_product_by_name "$prod_name")
    if [ -z "$prod_data" ]; then
        echo "{\"exists\": false, \"assigned_correctly\": false}"
        return
    fi
    
    local prod_id=$(echo "$prod_data" | cut -f1)
    
    # Get assigned categories
    local cats=$(get_product_categories "$prod_id")
    
    # Check if target category is in list (case insensitive)
    local assigned="false"
    if echo "$cats" | grep -qi "$target_cat"; then
        assigned="true"
    fi
    
    # Escape for JSON
    local cats_esc=$(json_escape "$cats")
    local name_esc=$(json_escape "$prod_name")
    
    echo "{\"exists\": true, \"id\": $prod_id, \"name\": \"$name_esc\", \"categories\": \"$cats_esc\", \"assigned_correctly\": $assigned}"
}

PROD1_JSON=$(check_product_category "Organic Cotton T-Shirt" "Tops")
PROD2_JSON=$(check_product_category "Merino Wool Sweater" "Tops")
PROD3_JSON=$(check_product_category "Slim Fit Denim Jeans" "Bottoms")

# 3. Final Category Count
INITIAL_COUNT=$(cat /tmp/initial_category_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_category_count 2>/dev/null || echo "0")

# ==============================================================================
# JSON CONSTRUCTION
# ==============================================================================

TEMP_JSON=$(mktemp /tmp/hierarchy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "counts": {
        "initial": $INITIAL_COUNT,
        "current": $CURRENT_COUNT
    },
    "categories": {
        "apparel": $APPAREL_JSON,
        "tops": $TOPS_JSON,
        "bottoms": $BOTTOMS_JSON
    },
    "products": {
        "tshirt": $PROD1_JSON,
        "sweater": $PROD2_JSON,
        "jeans": $PROD3_JSON
    },
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to standard location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
echo "=== Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="