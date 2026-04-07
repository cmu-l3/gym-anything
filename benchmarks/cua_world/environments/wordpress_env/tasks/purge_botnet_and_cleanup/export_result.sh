#!/bin/bash
# Export script for purge_botnet_and_cleanup task (post_task hook)

echo "=== Exporting purge_botnet_and_cleanup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# ============================================================
# Measure Current State
# ============================================================

# 1. Registration Settings
CURRENT_USERS_CAN_REGISTER=$(wp_cli option get users_can_register 2>/dev/null || echo "unknown")
CURRENT_DEFAULT_ROLE=$(wp_cli option get default_role 2>/dev/null || echo "unknown")

# 2. Contributor Accounts
CURRENT_CONTRIBUTOR_COUNT=$(wp_cli user list --role=contributor --format=count 2>/dev/null || echo "0")

# 3. Spam Master existence
if wp_cli user get spam_master --field=ID >/dev/null 2>&1; then
    SPAM_MASTER_EXISTS="true"
else
    SPAM_MASTER_EXISTS="false"
fi

# 4. Spam Master Content existence
SPAM_POSTS_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_title LIKE 'Spam Post%' AND post_type='post' AND post_status != 'trash'" 2>/dev/null || echo "0")

# 5. Orphaned (Empty) Tags
CURRENT_EMPTY_TAGS=$(wp_db_query "SELECT COUNT(*) FROM wp_term_taxonomy WHERE taxonomy='post_tag' AND count=0" 2>/dev/null || echo "0")

# 6. Legitimate State (Anti-gaming)
CURRENT_AUTHOR_COUNT=$(wp_cli user list --role=author --format=count 2>/dev/null || echo "0")
CURRENT_ACTIVE_TAGS=$(wp_db_query "SELECT COUNT(*) FROM wp_term_taxonomy WHERE taxonomy='post_tag' AND count>0" 2>/dev/null || echo "0")

# Output measurements to console for debugging
echo "Settings - users_can_register: $CURRENT_USERS_CAN_REGISTER, default_role: $CURRENT_DEFAULT_ROLE"
echo "Contributor count: $CURRENT_CONTRIBUTOR_COUNT"
echo "Spam master exists: $SPAM_MASTER_EXISTS"
echo "Spam posts count: $SPAM_POSTS_COUNT"
echo "Empty tags count: $CURRENT_EMPTY_TAGS"
echo "Author count: $CURRENT_AUTHOR_COUNT"
echo "Active tags: $CURRENT_ACTIVE_TAGS"

# ============================================================
# Create JSON result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "users_can_register": "$CURRENT_USERS_CAN_REGISTER",
    "default_role": "$CURRENT_DEFAULT_ROLE",
    "contributor_count": $CURRENT_CONTRIBUTOR_COUNT,
    "spam_master_exists": $SPAM_MASTER_EXISTS,
    "spam_posts_count": $SPAM_POSTS_COUNT,
    "empty_tags_count": $CURRENT_EMPTY_TAGS,
    "current_author_count": $CURRENT_AUTHOR_COUNT,
    "current_active_tags": $CURRENT_ACTIVE_TAGS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/purge_botnet_result.json 2>/dev/null || sudo rm -f /tmp/purge_botnet_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/purge_botnet_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/purge_botnet_result.json
chmod 666 /tmp/purge_botnet_result.json 2>/dev/null || sudo chmod 666 /tmp/purge_botnet_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/purge_botnet_result.json"
cat /tmp/purge_botnet_result.json
echo ""
echo "=== Export complete ==="