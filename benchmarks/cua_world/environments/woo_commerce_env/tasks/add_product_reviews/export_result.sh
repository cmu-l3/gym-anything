#!/bin/bash
# Export script for Add Product Reviews task

echo "=== Exporting Add Product Reviews Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REVIEWS=$(cat /tmp/initial_review_count.txt 2>/dev/null || echo "0")

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Settings
ENABLE_REVIEWS=$(wp option get woocommerce_enable_reviews --allow-root 2>/dev/null)
ENABLE_RATINGS=$(wp option get woocommerce_enable_review_rating --allow-root 2>/dev/null)
RATINGS_REQUIRED=$(wp option get woocommerce_review_rating_required --allow-root 2>/dev/null)

# 2. Check for Headphones Review
# Get Product ID
HP_DATA=$(get_product_by_sku "WBH-001")
HP_ID=$(echo "$HP_DATA" | cut -f1)

HP_REVIEW_FOUND="false"
HP_RATING=""
HP_CONTENT=""

if [ -n "$HP_ID" ]; then
    # Look for review created after task start containing keywords
    # Note: WooCommerce reviews are comments with comment_type 'review' or sometimes empty type on product posts
    # We join with commentmeta to get the rating
    QUERY="SELECT c.comment_content, cm.meta_value 
           FROM wp_comments c
           JOIN wp_commentmeta cm ON c.comment_ID = cm.comment_id
           WHERE c.comment_post_ID = $HP_ID
           AND cm.meta_key = 'rating'
           AND c.comment_date >= FROM_UNIXTIME($TASK_START)
           AND c.comment_content LIKE '%noise cancellation%'
           ORDER BY c.comment_ID DESC LIMIT 1"
    
    RESULT=$(wc_query "$QUERY")
    
    if [ -n "$RESULT" ]; then
        HP_REVIEW_FOUND="true"
        HP_CONTENT=$(echo "$RESULT" | cut -f1)
        HP_RATING=$(echo "$RESULT" | cut -f2)
    fi
fi

# 3. Check for T-Shirt Review
TS_DATA=$(get_product_by_sku "OCT-BLK-M")
TS_ID=$(echo "$TS_DATA" | cut -f1)

TS_REVIEW_FOUND="false"
TS_RATING=""
TS_CONTENT=""

if [ -n "$TS_ID" ]; then
    QUERY="SELECT c.comment_content, cm.meta_value 
           FROM wp_comments c
           JOIN wp_commentmeta cm ON c.comment_ID = cm.comment_id
           WHERE c.comment_post_ID = $TS_ID
           AND cm.meta_key = 'rating'
           AND c.comment_date >= FROM_UNIXTIME($TASK_START)
           AND c.comment_content LIKE '%sizing down%'
           ORDER BY c.comment_ID DESC LIMIT 1"
    
    RESULT=$(wc_query "$QUERY")
    
    if [ -n "$RESULT" ]; then
        TS_REVIEW_FOUND="true"
        TS_CONTENT=$(echo "$RESULT" | cut -f1)
        TS_RATING=$(echo "$RESULT" | cut -f2)
    fi
fi

# 4. Check total reviews count (Anti-gaming)
CURRENT_REVIEWS=$(wc_query "SELECT COUNT(*) FROM wp_comments WHERE comment_type='review' OR (comment_type='' AND comment_post_ID IN (SELECT ID FROM wp_posts WHERE post_type='product'))" 2>/dev/null || echo "0")
REVIEWS_ADDED=$((CURRENT_REVIEWS - INITIAL_REVIEWS))

# Escape strings for JSON
HP_CONTENT_ESC=$(json_escape "$HP_CONTENT")
TS_CONTENT_ESC=$(json_escape "$TS_CONTENT")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings": {
        "enable_reviews": "$ENABLE_REVIEWS",
        "enable_ratings": "$ENABLE_RATINGS",
        "ratings_required": "$RATINGS_REQUIRED"
    },
    "headphones_review": {
        "found": $HP_REVIEW_FOUND,
        "rating": "${HP_RATING:-0}",
        "content": "$HP_CONTENT_ESC"
    },
    "tshirt_review": {
        "found": $TS_REVIEW_FOUND,
        "rating": "${TS_RATING:-0}",
        "content": "$TS_CONTENT_ESC"
    },
    "stats": {
        "initial_count": $INITIAL_REVIEWS,
        "current_count": $CURRENT_REVIEWS,
        "reviews_added": $REVIEWS_ADDED
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo "=== Export Complete ==="