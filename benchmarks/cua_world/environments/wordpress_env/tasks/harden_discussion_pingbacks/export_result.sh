#!/bin/bash
# Export script for harden_discussion_pingbacks task
# Gathers verification data and exports to JSON

echo "=== Exporting harden_discussion_pingbacks result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Check Global Settings
# ============================================================
DEFAULT_PING_STATUS=$(wp_cli option get default_ping_status 2>/dev/null || echo "unknown")
CLOSE_COMMENTS=$(wp_cli option get close_comments_for_old_posts 2>/dev/null || echo "0")
CLOSE_DAYS=$(wp_cli option get close_comments_days_old 2>/dev/null || echo "0")
MAX_LINKS=$(wp_cli option get comment_max_links 2>/dev/null || echo "0")

echo "Global Settings:"
echo "  default_ping_status: $DEFAULT_PING_STATUS"
echo "  close_comments_for_old_posts: $CLOSE_COMMENTS"
echo "  close_comments_days_old: $CLOSE_DAYS"
echo "  comment_max_links: $MAX_LINKS"

# ============================================================
# Check Retroactive Bulk Edit
# ============================================================
# Count how many published posts STILL have ping_status = 'open'
OPEN_PINGS_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='post' AND post_status='publish' AND ping_status='open'" 2>/dev/null || echo "0")

echo "Retroactive Settings:"
echo "  open_ping_posts_count: $OPEN_PINGS_COUNT"

# ============================================================
# Check Comment Moderation Queue
# ============================================================
# Count pending pingbacks
PENDING_PINGBACKS=$(wp_db_query "SELECT COUNT(*) FROM wp_comments WHERE comment_type='pingback' AND comment_approved='0'" 2>/dev/null || echo "0")

# Check if legitimate comment is still there and NOT spam/trash
# Approved ('1') or Pending ('0') is fine, 'spam' or 'trash' is fail
LEGIT_COMMENT_EXISTS="false"
LEGIT_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_comments WHERE comment_author='Jane Doe' AND comment_content LIKE '%Great article!%' AND comment_approved IN ('0', '1')" 2>/dev/null || echo "0")
if [ "$LEGIT_COUNT" -gt 0 ] 2>/dev/null; then
    LEGIT_COMMENT_EXISTS="true"
fi

echo "Queue Status:"
echo "  pending_pingbacks: $PENDING_PINGBACKS"
echo "  legit_comment_exists: $LEGIT_COMMENT_EXISTS"

# ============================================================
# Create JSON Export
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings": {
        "default_ping_status": "$DEFAULT_PING_STATUS",
        "close_comments": "$CLOSE_COMMENTS",
        "close_days": "$CLOSE_DAYS",
        "max_links": "$MAX_LINKS"
    },
    "posts": {
        "open_pings_count": $OPEN_PINGS_COUNT
    },
    "comments": {
        "pending_pingbacks": $PENDING_PINGBACKS,
        "legit_comment_exists": $LEGIT_COMMENT_EXISTS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/harden_pingbacks_result.json 2>/dev/null || sudo rm -f /tmp/harden_pingbacks_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/harden_pingbacks_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/harden_pingbacks_result.json
chmod 666 /tmp/harden_pingbacks_result.json 2>/dev/null || sudo chmod 666 /tmp/harden_pingbacks_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/harden_pingbacks_result.json"
cat /tmp/harden_pingbacks_result.json
echo ""
echo "=== Export complete ==="