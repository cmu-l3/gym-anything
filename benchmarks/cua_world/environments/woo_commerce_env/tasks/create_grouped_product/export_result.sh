#!/bin/bash
# Export script for Create Grouped Product task

echo "=== Exporting Create Grouped Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "product_found": false}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get timestamps/counts
INITIAL_COUNT=$(cat /tmp/initial_grouped_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts p
    JOIN wp_term_relationships tr ON p.ID = tr.object_id
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    WHERE p.post_type = 'product' AND p.post_status = 'publish'
    AND t.slug = 'grouped' AND tt.taxonomy = 'product_type'" 2>/dev/null || echo "0")

# Find the product by name "Tech Essentials Bundle"
echo "Searching for product 'Tech Essentials Bundle'..."
PRODUCT_DATA=$(wc_query "SELECT ID, post_title, post_status, post_excerpt, post_content
    FROM wp_posts
    WHERE post_type = 'product'
    AND LOWER(post_title) LIKE '%tech essentials bundle%'
    ORDER BY ID DESC LIMIT 1" 2>/dev/null)

PRODUCT_FOUND="false"
PID=""
PTITLE=""
PSTATUS=""
PEXCERPT=""
PCONTENT=""
PTYPE=""
PCATEGORIES=""
CHILDREN_META=""
CHILD_IDS_FOUND="[]"
HEADPHONES_ID=""
CHARGER_ID=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PID=$(echo "$PRODUCT_DATA" | cut -f1)
    PTITLE=$(echo "$PRODUCT_DATA" | cut -f2)
    PSTATUS=$(echo "$PRODUCT_DATA" | cut -f3)
    PEXCERPT=$(echo "$PRODUCT_DATA" | cut -f4)
    PCONTENT=$(echo "$PRODUCT_DATA" | cut -f5)
    
    # Get Product Type
    PTYPE=$(get_product_type "$PID" 2>/dev/null)
    
    # Get Categories
    PCATEGORIES=$(get_product_categories "$PID" 2>/dev/null)
    
    # Get Linked Children (_children postmeta)
    # WooCommerce stores this as a PHP serialized array. 
    # Example: a:2:{i:0;i:15;i:1;i:16;}
    CHILDREN_META=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PID AND meta_key='_children' LIMIT 1" 2>/dev/null)
    
    # Resolve IDs of expected children to check against meta
    # Wireless Bluetooth Headphones (SKU: WBH-001)
    H_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
    if [ -n "$H_DATA" ]; then
        HEADPHONES_ID=$(echo "$H_DATA" | cut -f1)
    fi
    
    # USB-C Laptop Charger 65W (SKU: USBC-065)
    C_DATA=$(get_product_by_sku "USBC-065" 2>/dev/null)
    if [ -n "$C_DATA" ]; then
        CHARGER_ID=$(echo "$C_DATA" | cut -f1)
    fi
    
    # Build a simple JSON array of found children IDs for the verifier
    # We grep the serialized string because we can't easily unserialize PHP in bash
    CHILD_IDS_FOUND="["
    COMMA=""
    if [ -n "$HEADPHONES_ID" ] && [[ "$CHILDREN_META" == *"$HEADPHONES_ID"* ]]; then
        CHILD_IDS_FOUND="${CHILD_IDS_FOUND}\"WBH-001\""
        COMMA=","
    fi
    if [ -n "$CHARGER_ID" ] && [[ "$CHILDREN_META" == *"$CHARGER_ID"* ]]; then
        CHILD_IDS_FOUND="${CHILD_IDS_FOUND}${COMMA}\"USBC-065\""
    fi
    CHILD_IDS_FOUND="${CHILD_IDS_FOUND}]"
fi

# Escape strings for JSON
PTITLE_ESC=$(json_escape "$PTITLE")
PEXCERPT_ESC=$(json_escape "$PEXCERPT")
PCONTENT_ESC=$(json_escape "$PCONTENT")
PCATEGORIES_ESC=$(json_escape "$PCATEGORIES")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_grouped_count": ${INITIAL_COUNT:-0},
    "current_grouped_count": ${CURRENT_COUNT:-0},
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PID",
        "title": "$PTITLE_ESC",
        "status": "$PSTATUS",
        "type": "$PTYPE",
        "categories": "$PCATEGORIES_ESC",
        "short_description": "$PEXCERPT_ESC",
        "description": "$PCONTENT_ESC",
        "linked_children_skus": $CHILD_IDS_FOUND
    },
    "metadata": {
        "headphones_id": "$HEADPHONES_ID",
        "charger_id": "$CHARGER_ID",
        "raw_children_meta": "$(json_escape "$CHILDREN_META")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="