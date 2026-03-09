#!/bin/bash
# Export script for Duplicate Product Variant task

echo "=== Exporting Duplicate Product Variant Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SOURCE_ID=$(cat /tmp/source_product_id.txt 2>/dev/null || echo "0")

# 1. Find the new product by expected SKU
echo "Searching for product with SKU: WBH-001-GOLD..."
TARGET_DATA=$(get_product_by_sku "WBH-001-GOLD" 2>/dev/null)

PRODUCT_FOUND="false"
PID=""
TITLE=""
STATUS=""
PRICE=""
DESCRIPTION=""
VISIBILITY_TERMS="[]"
IS_NEW="false"

if [ -n "$TARGET_DATA" ]; then
    PRODUCT_FOUND="true"
    PID=$(echo "$TARGET_DATA" | cut -f1)
    
    # Get basic details
    TITLE=$(wc_query "SELECT post_title FROM wp_posts WHERE ID=$PID")
    STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$PID")
    PRICE=$(get_product_price "$PID")
    DESCRIPTION=$(wc_query "SELECT post_content FROM wp_posts WHERE ID=$PID")
    
    # Check creation time to ensure it was created DURING task
    POST_DATE=$(wc_query "SELECT post_date_gmt FROM wp_posts WHERE ID=$PID")
    POST_TIMESTAMP=$(date -d "$POST_DATE" +%s)
    
    # Allow 60s tolerance for clock drift, but generally post_date should be >= task_start
    # Note: docker containers might have slight time diffs, but usually synced
    if [ "$POST_TIMESTAMP" -ge "$((TASK_START - 60))" ]; then
        IS_NEW="true"
    fi
    
    # Check Visibility (product_visibility taxonomy)
    # Returns terms like 'exclude-from-catalog', 'exclude-from-search'
    # "Search results only" means 'exclude-from-catalog' is present
    TERMS_RAW=$(wc_query "SELECT t.slug FROM wp_terms t 
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id 
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id 
        WHERE tr.object_id = $PID AND tt.taxonomy = 'product_visibility'")
    
    # Convert newline separated terms to JSON array
    VISIBILITY_TERMS=$(echo "$TERMS_RAW" | jq -R -s -c 'split("\n")[:-1]')
fi

# Get source description for comparison (handled in verifier, but export text here)
SOURCE_DESC_CONTENT=$(cat /tmp/source_description.txt 2>/dev/null || echo "")

# Escape strings for JSON
TITLE_ESC=$(json_escape "$TITLE")
DESC_ESC=$(json_escape "$DESCRIPTION")
SOURCE_DESC_ESC=$(json_escape "$SOURCE_DESC_CONTENT")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product": {
        "id": "$PID",
        "title": "$TITLE_ESC",
        "status": "$STATUS",
        "price": "$PRICE",
        "description": "$DESC_ESC",
        "visibility_terms": $VISIBILITY_TERMS,
        "is_new": $IS_NEW
    },
    "source_description": "$SOURCE_DESC_ESC",
    "source_id": "$SOURCE_ID",
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json