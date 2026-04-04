#!/bin/bash
# Export script for create_blog_post task (post_task hook)
# Gathers verification data and exports to JSON

echo "=== Exporting create_blog_post result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial counts
INITIAL_POST_COUNT=$(cat /tmp/initial_post_count 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_total_post_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_POST_COUNT=$(get_post_count "post" "publish")
CURRENT_TOTAL_COUNT=$(wp_cli post list --post_type=post --format=count)

echo "Initial published: $INITIAL_POST_COUNT, Current published: $CURRENT_POST_COUNT"
echo "Initial total: $INITIAL_TOTAL_COUNT, Current total: $CURRENT_TOTAL_COUNT"

# Expected values
EXPECTED_TITLE="The Future of Artificial Intelligence in Healthcare"
EXPECTED_CATEGORY="Technology"

# Search for the post by title (case-insensitive)
POST_FOUND="false"
POST_ID=""
POST_TITLE=""
POST_STATUS=""
POST_CONTENT=""
POST_CATEGORIES=""
POST_TAGS=""
CONTENT_LENGTH=0

# Try exact title match first
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$EXPECTED_TITLE')) AND post_type='post' AND post_status IN ('publish', 'draft', 'pending') ORDER BY ID DESC LIMIT 1")

# If not found, try partial match (must contain both "artificial intelligence" AND "healthcare")
if [ -z "$POST_ID" ]; then
    echo "Exact title not found, trying partial match..."
    POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(post_title) LIKE '%artificial intelligence%' AND LOWER(post_title) LIKE '%healthcare%' AND post_type='post' ORDER BY ID DESC LIMIT 1")
fi

# NOTE: Removed "any new post" fallback - agent MUST create post with correct title
# This prevents adversarial bypass where agent creates a random post with correct content/tags
if [ -z "$POST_ID" ] && [ "$CURRENT_TOTAL_COUNT" -gt "$INITIAL_TOTAL_COUNT" ]; then
    echo "WARNING: New post(s) created but title does not match expected pattern"
    echo "Expected title containing 'artificial intelligence' AND 'healthcare'"
    # Do NOT fall back to any new post - this would enable bypass
fi

if [ -n "$POST_ID" ]; then
    POST_FOUND="true"
    echo "Found post with ID: $POST_ID"

    # Get post details
    POST_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$POST_ID")
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID")
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID")
    CONTENT_LENGTH=${#POST_CONTENT}

    # Get categories
    POST_CATEGORIES=$(get_post_categories "$POST_ID")

    # Get tags
    POST_TAGS=$(get_post_tags "$POST_ID")

    echo "Post title: $POST_TITLE"
    echo "Post status: $POST_STATUS"
    echo "Content length: $CONTENT_LENGTH"
    echo "Categories: $POST_CATEGORIES"
    echo "Tags: $POST_TAGS"
else
    echo "No matching post found"
fi

# Escape content for JSON (remove newlines, escape quotes)
ESCAPED_CONTENT=$(echo "$POST_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 5000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_post_count": $INITIAL_POST_COUNT,
    "current_post_count": $CURRENT_POST_COUNT,
    "initial_total_count": $INITIAL_TOTAL_COUNT,
    "current_total_count": $CURRENT_TOTAL_COUNT,
    "post_found": $POST_FOUND,
    "post": {
        "id": "${POST_ID:-}",
        "title": "$(echo "$POST_TITLE" | sed 's/"/\\"/g' | tr -d '\n')",
        "status": "${POST_STATUS:-}",
        "content": "$ESCAPED_CONTENT",
        "content_length": $CONTENT_LENGTH,
        "categories": "$(echo "$POST_CATEGORIES" | sed 's/"/\\"/g')",
        "tags": "$(echo "$POST_TAGS" | sed 's/"/\\"/g')"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/create_blog_post_result.json 2>/dev/null || sudo rm -f /tmp/create_blog_post_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_blog_post_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_blog_post_result.json
chmod 666 /tmp/create_blog_post_result.json 2>/dev/null || sudo chmod 666 /tmp/create_blog_post_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/create_blog_post_result.json"
cat /tmp/create_blog_post_result.json
echo ""
echo "=== Export complete ==="
