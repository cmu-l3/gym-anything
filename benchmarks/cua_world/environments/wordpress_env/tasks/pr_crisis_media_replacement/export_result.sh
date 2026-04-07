#!/bin/bash
set -e
echo "=== Exporting PR Crisis task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Read the original media path saved during setup
MEDIA_PATH=$(cat /tmp/original_media_path.txt 2>/dev/null)
FILE_FULL_PATH="/var/www/html/wordpress/wp-content/uploads/$MEDIA_PATH"

FILE_EXISTS="false"
CONTAINS_CORRECTED="false"

# Check if the file at the exact original path exists and contains the corrected value ($500000)
if [ -f "$FILE_FULL_PATH" ]; then
    FILE_EXISTS="true"
    if grep -q "500000" "$FILE_FULL_PATH"; then
        CONTAINS_CORRECTED="true"
    fi
fi

# Check original post for the correction note
ORIGINAL_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Q3 2024 Financial Results Announced' AND post_status='publish' LIMIT 1")
ORIGINAL_POST_CONTENT=""

if [ -n "$ORIGINAL_POST_ID" ]; then
    ORIGINAL_POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$ORIGINAL_POST_ID")
fi

# Check new embargoed post
NEW_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Embargoed: Q3 Corrected Figures Summary' LIMIT 1")
NEW_POST_STATUS=""
NEW_POST_DATE=""
HAS_TAG="false"

if [ -n "$NEW_POST_ID" ]; then
    NEW_POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$NEW_POST_ID")
    NEW_POST_DATE=$(wp_db_query "SELECT post_date FROM wp_posts WHERE ID=$NEW_POST_ID")
    
    # Check if the "Press Release" tag is assigned
    TAGS=$(get_post_tags "$NEW_POST_ID")
    if echo "$TAGS" | grep -qi "Press Release"; then
        HAS_TAG="true"
    fi
fi

# Escape content for JSON safety
ESCAPED_CONTENT=$(echo "$ORIGINAL_POST_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | head -c 5000)

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "contains_corrected": $CONTAINS_CORRECTED,
    "original_media_path": "${MEDIA_PATH:-}",
    "original_post_content": "$ESCAPED_CONTENT",
    "new_post_found": $([ -n "$NEW_POST_ID" ] && echo "true" || echo "false"),
    "new_post_status": "${NEW_POST_STATUS:-}",
    "new_post_date": "${NEW_POST_DATE:-}",
    "has_press_release_tag": $HAS_TAG,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/pr_crisis_result.json 2>/dev/null || sudo rm -f /tmp/pr_crisis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pr_crisis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pr_crisis_result.json
chmod 666 /tmp/pr_crisis_result.json 2>/dev/null || sudo chmod 666 /tmp/pr_crisis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/pr_crisis_result.json"
cat /tmp/pr_crisis_result.json
echo "=== Export complete ==="