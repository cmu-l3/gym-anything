#!/bin/bash
# Export script for format_longform_article task
echo "=== Exporting format_longform_article result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPECTED_TITLE="Renewable Energy Deployment and Technologies"
POST_FOUND="false"
POST_ID=""
POST_STATUS=""
POST_CONTENT=""
POST_CATEGORIES=""

# Try to find the post by exact title
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$EXPECTED_TITLE')) AND post_type='post' AND post_status IN ('publish', 'draft') ORDER BY ID DESC LIMIT 1")

if [ -n "$POST_ID" ]; then
    POST_FOUND="true"
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID")
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID")
    POST_CATEGORIES=$(get_post_categories "$POST_ID")
    echo "Found post: $EXPECTED_TITLE (ID: $POST_ID, Status: $POST_STATUS)"
else
    echo "Expected post title not found in database."
fi

# Escape content for JSON export
if [ -n "$POST_CONTENT" ]; then
    ESCAPED_CONTENT=$(echo "$POST_CONTENT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r//g')
else
    ESCAPED_CONTENT=""
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "post_found": $POST_FOUND,
    "post_id": "${POST_ID:-}",
    "post_status": "${POST_STATUS:-}",
    "post_categories": "$(echo "$POST_CATEGORIES" | sed 's/"/\\"/g')",
    "post_content": "$ESCAPED_CONTENT",
    "timestamp": "$(date +%s)"
}
EOF

# Move to final location safely
rm -f /tmp/format_longform_article_result.json 2>/dev/null || sudo rm -f /tmp/format_longform_article_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/format_longform_article_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/format_longform_article_result.json
chmod 666 /tmp/format_longform_article_result.json 2>/dev/null || sudo chmod 666 /tmp/format_longform_article_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
echo "=== Export complete ==="