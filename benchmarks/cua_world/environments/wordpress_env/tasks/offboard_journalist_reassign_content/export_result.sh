#!/bin/bash
# Export script for offboard_journalist_reassign_content task (post_task hook)

echo "=== Exporting offboard_journalist_reassign_content result ==="

source /workspace/scripts/task_utils.sh
source /tmp/task_post_ids.sh
cd /var/www/html/wordpress

take_screenshot /tmp/task_final.png

# 1. Check if target user 'jdoe' is deleted
JDOE_EXISTS="false"
if wp user get jdoe --field=ID --allow-root 2>/dev/null >/dev/null; then
    JDOE_EXISTS="true"
fi

# 2. Check if archive user is created correctly
ARCHIVE_EXISTS="false"
ARCHIVE_ROLE=""
ARCHIVE_EMAIL=""
ARCHIVE_ID=""

if wp user get editorial_archives --field=ID --allow-root 2>/dev/null >/dev/null; then
    ARCHIVE_EXISTS="true"
    ARCHIVE_ID=$(wp user get editorial_archives --field=ID --allow-root)
    ARCHIVE_ROLE=$(wp user get editorial_archives --field=roles --allow-root)
    ARCHIVE_EMAIL=$(wp user get editorial_archives --field=user_email --allow-root)
fi

# 3. Check JDOE's published posts (should be reassigned to ARCHIVE_ID and still published)
JDOE_PUB_CORRECT_COUNT=0
for id in "${JDOE_PUB_IDS[@]}"; do
    AUTHOR=$(wp_db_query "SELECT post_author FROM wp_posts WHERE ID=$id")
    STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$id")
    
    # If the archive user exists and matches the new author, and it is still published
    if [ "$ARCHIVE_EXISTS" = "true" ] && [ "$AUTHOR" = "$ARCHIVE_ID" ] && [ "$STATUS" = "publish" ]; then
        JDOE_PUB_CORRECT_COUNT=$((JDOE_PUB_CORRECT_COUNT + 1))
    fi
done

# 4. Check JDOE's drafts (should be trashed)
JDOE_DRAFTS_TRASHED_COUNT=0
for id in "${JDOE_DRAFT_IDS[@]}"; do
    STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$id")
    if [ "$STATUS" = "trash" ]; then
        JDOE_DRAFTS_TRASHED_COUNT=$((JDOE_DRAFTS_TRASHED_COUNT + 1))
    fi
done

# 5. Check Bystander (Alice Smith) posts - ensuring no collateral damage
ASMITH_ID=$(wp user get asmith --field=ID --allow-root 2>/dev/null || echo "0")
ASMITH_POSTS_INTACT_COUNT=0
for id in "${ASMITH_PUB_IDS[@]}"; do
    AUTHOR=$(wp_db_query "SELECT post_author FROM wp_posts WHERE ID=$id")
    STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$id")
    
    if [ "$AUTHOR" = "$ASMITH_ID" ] && [ "$STATUS" = "publish" ]; then
        ASMITH_POSTS_INTACT_COUNT=$((ASMITH_POSTS_INTACT_COUNT + 1))
    fi
done

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "jdoe_exists": $JDOE_EXISTS,
    "archive_exists": $ARCHIVE_EXISTS,
    "archive_id": "${ARCHIVE_ID:-0}",
    "archive_role": "$ARCHIVE_ROLE",
    "archive_email": "$ARCHIVE_EMAIL",
    "jdoe_pub_correct_count": $JDOE_PUB_CORRECT_COUNT,
    "jdoe_pub_expected": ${#JDOE_PUB_IDS[@]},
    "jdoe_drafts_trashed_count": $JDOE_DRAFTS_TRASHED_COUNT,
    "jdoe_drafts_expected": ${#JDOE_DRAFT_IDS[@]},
    "asmith_posts_intact_count": $ASMITH_POSTS_INTACT_COUNT,
    "asmith_posts_expected": ${#ASMITH_PUB_IDS[@]},
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/offboard_journalist_result.json 2>/dev/null || sudo rm -f /tmp/offboard_journalist_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/offboard_journalist_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/offboard_journalist_result.json
chmod 666 /tmp/offboard_journalist_result.json 2>/dev/null || sudo chmod 666 /tmp/offboard_journalist_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/offboard_journalist_result.json