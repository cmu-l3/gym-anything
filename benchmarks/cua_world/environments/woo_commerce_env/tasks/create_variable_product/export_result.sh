#!/bin/bash
# Export script for Create Variable Product task
set -e

echo "=== Exporting Create Variable Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check DB Connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# 3. Find Product
# We look for the newest product with the expected name
PRODUCT_DATA=$(wc_query "SELECT ID, post_title, post_status, post_date 
    FROM wp_posts 
    WHERE post_type='product' AND post_title='Handcrafted Ceramic Mug' 
    ORDER BY ID DESC LIMIT 1" 2>/dev/null)

FOUND="false"
PID=""
TITLE=""
STATUS=""
CREATED_DATE=""
SKU=""
TYPE=""
CATS=""
ATTRIBUTES_RAW=""
VARIATIONS_JSON="[]"

if [ -n "$PRODUCT_DATA" ]; then
    FOUND="true"
    PID=$(echo "$PRODUCT_DATA" | cut -f1)
    TITLE=$(echo "$PRODUCT_DATA" | cut -f2)
    STATUS=$(echo "$PRODUCT_DATA" | cut -f3)
    CREATED_DATE=$(echo "$PRODUCT_DATA" | cut -f4)

    # Get Metadata
    SKU=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PID AND meta_key='_sku' LIMIT 1" 2>/dev/null)
    
    # Check if variable
    TYPE=$(get_product_type "$PID" 2>/dev/null)
    
    # Get Category
    CATS=$(get_product_categories "$PID" 2>/dev/null)
    
    # Get Attributes (Raw Serialized String)
    ATTRIBUTES_RAW=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PID AND meta_key='_product_attributes' LIMIT 1" 2>/dev/null)
    
    # Get Variations
    # Get list of variation IDs
    VAR_IDS=$(wc_query "SELECT ID FROM wp_posts WHERE post_parent=$PID AND post_type='product_variation' AND post_status IN ('publish', 'private')" 2>/dev/null)
    
    # Construct Variations JSON
    VARIATIONS_JSON="["
    FIRST_VAR=true
    
    for VID in $VAR_IDS; do
        if [ "$FIRST_VAR" = true ]; then FIRST_VAR=false; else VARIATIONS_JSON="$VARIATIONS_JSON,"; fi
        
        V_PRICE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$VID AND meta_key='_regular_price' LIMIT 1" 2>/dev/null)
        V_STOCK=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$VID AND meta_key='_stock' LIMIT 1" 2>/dev/null)
        V_MANAGE_STOCK=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$VID AND meta_key='_manage_stock' LIMIT 1" 2>/dev/null)
        
        # Get attributes defined for this variation (e.g., attribute_pa_size or attribute_size)
        # We grab all meta keys starting with attribute_ for this variation
        V_ATTRS=$(wc_query "SELECT GROUP_CONCAT(CONCAT(meta_key, ':', meta_value)) FROM wp_postmeta WHERE post_id=$VID AND meta_key LIKE 'attribute_%'" 2>/dev/null)
        
        VARIATIONS_JSON="$VARIATIONS_JSON {
            \"id\": \"$VID\",
            \"regular_price\": \"$V_PRICE\",
            \"stock_quantity\": \"$V_STOCK\",
            \"manage_stock\": \"$V_MANAGE_STOCK\",
            \"attributes_meta\": \"$V_ATTRS\"
        }"
    done
    VARIATIONS_JSON="$VARIATIONS_JSON]"
fi

# 4. JSON Generation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "product_found": $FOUND,
    "product": {
        "id": "$PID",
        "title": "$(json_escape "$TITLE")",
        "sku": "$(json_escape "$SKU")",
        "type": "$TYPE",
        "status": "$STATUS",
        "categories": "$(json_escape "$CATS")",
        "created_date": "$CREATED_DATE",
        "attributes_raw": "$(json_escape "$ATTRIBUTES_RAW")"
    },
    "variations": $VARIATIONS_JSON
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json