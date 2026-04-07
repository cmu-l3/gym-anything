#!/bin/bash
# Export script for resolve_fatal_error_and_optimize task

echo "=== Exporting resolve_fatal_error_and_optimize result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# 1. Check Site HTTP Status
# ============================================================
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
echo "Site HTTP Status: $HTTP_STATUS"

# ============================================================
# 2. Check if plugin directory exists
# ============================================================
PLUGIN_DIR="/var/www/html/wordpress/wp-content/plugins/broken-analytics"
PLUGIN_EXISTS="false"
if [ -d "$PLUGIN_DIR" ]; then
    PLUGIN_EXISTS="true"
fi
echo "Plugin directory exists: $PLUGIN_EXISTS"

# ============================================================
# 3. Check Database State (Safely via DB Queries)
# ============================================================
# Count spam comments
SPAM_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_comments WHERE comment_approved = 'spam'" 2>/dev/null || echo "0")
echo "Spam comments: $SPAM_COUNT"

# Count approved comments (to ensure they weren't deleted)
VALID_COMMENTS_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_comments WHERE comment_approved = '1'" 2>/dev/null || echo "0")
echo "Valid comments: $VALID_COMMENTS_COUNT"

# Count post revisions
REVISION_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type = 'revision'" 2>/dev/null || echo "0")
echo "Post revisions: $REVISION_COUNT"

# Count published posts (to ensure valid data wasn't deleted)
VALID_POSTS_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type = 'post' AND post_status = 'publish'" 2>/dev/null || echo "0")
echo "Valid posts: $VALID_POSTS_COUNT"

# Check for the required incident report post
REPORT_POST_EXISTS="false"
REPORT_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type = 'post' AND post_status = 'publish' AND LOWER(TRIM(post_title)) = LOWER('System Outage Resolved') LIMIT 1" 2>/dev/null)
if [ -n "$REPORT_ID" ]; then
    REPORT_POST_EXISTS="true"
    echo "Report post found (ID: $REPORT_ID)"
else
    echo "Report post NOT found"
fi

# ============================================================
# 4. Export JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "http_status": "$HTTP_STATUS",
    "plugin_exists": $PLUGIN_EXISTS,
    "spam_count": $SPAM_COUNT,
    "valid_comments_count": $VALID_COMMENTS_COUNT,
    "revision_count": $REVISION_COUNT,
    "valid_posts_count": $VALID_POSTS_COUNT,
    "report_post_exists": $REPORT_POST_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/resolve_fatal_error_result.json 2>/dev/null || sudo rm -f /tmp/resolve_fatal_error_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/resolve_fatal_error_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/resolve_fatal_error_result.json
chmod 666 /tmp/resolve_fatal_error_result.json 2>/dev/null || sudo chmod 666 /tmp/resolve_fatal_error_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/resolve_fatal_error_result.json"
cat /tmp/resolve_fatal_error_result.json
echo "=== Export complete ==="