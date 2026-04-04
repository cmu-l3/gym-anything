#!/bin/bash
# Export script for Discontinue Product Legacy task

echo "=== Exporting Discontinue Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Target ID
TARGET_ID=$(cat /tmp/target_product_id 2>/dev/null)

if [ -z "$TARGET_ID" ]; then
    # Fallback search if setup didn't record ID or it changed
    TARGET_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_type='product' AND pm.meta_key='_sku' AND pm.meta_value='VCL-50MM' LIMIT 1" 2>/dev/null)
fi

PRODUCT_FOUND="false"
POST_STATUS=""
STOCK_STATUS=""
SHORT_DESCRIPTION=""
VISIBILITY_TERMS="[]"

if [ -n "$TARGET_ID" ]; then
    PRODUCT_FOUND="true"
    
    # Get basic post info
    POST_DATA=$(wc_query "SELECT post_status, post_excerpt FROM wp_posts WHERE ID=$TARGET_ID LIMIT 1")
    POST_STATUS=$(echo "$POST_DATA" | cut -f1)
    SHORT_DESCRIPTION=$(echo "$POST_DATA" | cut -f2)
    
    # Get stock status
    STOCK_STATUS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$TARGET_ID AND meta_key='_stock_status' LIMIT 1")
    
    # Get visibility terms
    # WooCommerce uses 'product_visibility' taxonomy. Terms: 'exclude-from-search', 'exclude-from-catalog'
    TERMS_RAW=$(wc_query "SELECT t.slug 
        FROM wp_terms t 
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id 
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id 
        WHERE tr.object_id = $TARGET_ID 
        AND tt.taxonomy = 'product_visibility'")
    
    # Convert newline separated terms to JSON array
    VISIBILITY_TERMS="["
    FIRST=true
    while read -r term; do
        if [ -n "$term" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                VISIBILITY_TERMS="$VISIBILITY_TERMS,"
            fi
            VISIBILITY_TERMS="$VISIBILITY_TERMS\"$term\""
        fi
    done <<< "$TERMS_RAW"
    VISIBILITY_TERMS="$VISIBILITY_TERMS]"
fi

# Escape description for JSON
SHORT_DESC_ESC=$(json_escape "$SHORT_DESCRIPTION")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/discontinue_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product_id": "$TARGET_ID",
    "post_status": "$POST_STATUS",
    "stock_status": "$STOCK_STATUS",
    "short_description": "$SHORT_DESC_ESC",
    "visibility_terms": $VISIBILITY_TERMS,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="