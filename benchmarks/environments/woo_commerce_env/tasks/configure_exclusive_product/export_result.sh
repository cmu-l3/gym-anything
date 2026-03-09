#!/bin/bash
# Export script for Configure Exclusive Product task

echo "=== Exporting Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Target Product ID
PID=$(cat /tmp/target_product_id.txt 2>/dev/null)
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$PID" ]; then
    # Fallback: search by name again
    PRODUCT_DATA=$(get_product_by_name "Wireless Bluetooth Headphones" 2>/dev/null)
    PID=$(echo "$PRODUCT_DATA" | cut -f1)
fi

# Initialize result variables
PRODUCT_FOUND="false"
SOLD_INDIVIDUALLY=""
VISIBILITY_TERMS="[]"
SHORT_DESC=""
LAST_MODIFIED="0"
MODIFIED_DURING_TASK="false"

if [ -n "$PID" ]; then
    PRODUCT_FOUND="true"
    
    # 1. Check Inventory Setting (_sold_individually)
    SOLD_INDIVIDUALLY=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PID AND meta_key='_sold_individually'")
    
    # 2. Check Visibility Terms (product_visibility taxonomy)
    # We need to see if 'exclude-from-catalog' or 'exclude-from-search' terms are applied
    TERMS_RAW=$(wc_query "SELECT t.slug 
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id
        WHERE tr.object_id = $PID 
        AND tt.taxonomy = 'product_visibility'")
        
    # Convert newline separated slugs to JSON array
    VISIBILITY_TERMS=$(echo "$TERMS_RAW" | jq -R -s -c 'split("\n")[:-1]')

    # 3. Check Short Description
    SHORT_DESC=$(wc_query "SELECT post_excerpt FROM wp_posts WHERE ID=$PID")
    
    # 4. Check Modification Time
    LAST_MODIFIED_STR=$(wc_query "SELECT post_modified_gmt FROM wp_posts WHERE ID=$PID")
    LAST_MODIFIED=$(date -d "$LAST_MODIFIED_STR" +%s)
    
    if [ "$LAST_MODIFIED" -gt "$START_TIME" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# Escape short description for JSON
SHORT_DESC_ESC=$(json_escape "$SHORT_DESC")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product_id": "$PID",
    "sold_individually_meta": "$SOLD_INDIVIDUALLY",
    "visibility_terms": $VISIBILITY_TERMS,
    "short_description": "$SHORT_DESC_ESC",
    "modified_timestamp": $LAST_MODIFIED,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "task_start_time": $START_TIME
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="