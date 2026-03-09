#!/bin/bash
# Export script for audit_reorganize_content task (post_task hook)
# Checks category assignments, spam deletion, draft publication, and tags.

echo "=== Exporting audit_reorganize_content result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Helper: check a post's category, status, and tags
# ============================================================
check_audit_post() {
    local title="$1"
    local expected_category="$2"
    local expected_status="$3"  # "publish" or "any" (don't care)
    local expected_tag="$4"     # tag to check for

    local post_id=""
    local found="false"
    local category_correct="false"
    local status_correct="false"
    local has_tag="false"
    local actual_category=""
    local actual_status=""
    local actual_tags=""

    # Find post by title (any status including trash)
    post_id=$(wp_db_query "SELECT ID FROM wp_posts
        WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$title'))
        AND post_type='post'
        AND post_status NOT IN ('trash', 'auto-draft')
        ORDER BY ID DESC LIMIT 1")

    if [ -n "$post_id" ]; then
        found="true"

        actual_status=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$post_id")
        actual_category=$(get_post_categories "$post_id")
        actual_tags=$(get_post_tags "$post_id")

        # Check category
        local cat_lower=$(echo "$actual_category" | tr '[:upper:]' '[:lower:]')
        local expected_cat_lower=$(echo "$expected_category" | tr '[:upper:]' '[:lower:]')
        if echo "$cat_lower" | grep -q "$expected_cat_lower"; then
            # Also check it's NOT still in Uncategorized
            if ! echo "$cat_lower" | grep -q "uncategorized" || [ "$expected_category" = "Uncategorized" ]; then
                category_correct="true"
            fi
        fi

        # Check status
        if [ "$expected_status" = "any" ]; then
            status_correct="true"
        elif [ "$(echo "$actual_status" | tr '[:upper:]' '[:lower:]')" = "$(echo "$expected_status" | tr '[:upper:]' '[:lower:]')" ]; then
            status_correct="true"
        fi

        # Check tag
        if [ -n "$expected_tag" ]; then
            local tags_lower=$(echo "$actual_tags" | tr '[:upper:]' '[:lower:]')
            local tag_lower=$(echo "$expected_tag" | tr '[:upper:]' '[:lower:]')
            if echo "$tags_lower" | grep -q "$tag_lower"; then
                has_tag="true"
            fi
        fi

        echo "  '$title' (ID: $post_id): cat=[$actual_category] status=$actual_status tags=[$actual_tags]"
    else
        echo "  '$title': NOT FOUND (may be trashed/deleted)"
    fi

    echo "{\"found\": $found, \"category_correct\": $category_correct, \"status_correct\": $status_correct, \"has_tag\": $has_tag, \"actual_category\": \"$(echo "$actual_category" | sed 's/"/\\"/g')\", \"actual_status\": \"$actual_status\", \"actual_tags\": \"$(echo "$actual_tags" | sed 's/"/\\"/g')\"}"
}

echo "Checking post states:"
echo ""

# Check 5 legitimate posts
P1_OUT=$(check_audit_post "Cloud Computing Trends 2026" "Technology" "publish" "featured")
P2_OUT=$(check_audit_post "AI in Software Development" "Technology" "publish" "featured")
P3_OUT=$(check_audit_post "Weekend Hiking Trail Guide" "Lifestyle" "any" "featured")
P4_OUT=$(check_audit_post "Healthy Meal Prep Ideas" "Lifestyle" "any" "featured")
P5_OUT=$(check_audit_post "Breaking: Local Business Awards Announced" "News" "publish" "featured")

P1_JSON=$(echo "$P1_OUT" | tail -1)
P2_JSON=$(echo "$P2_OUT" | tail -1)
P3_JSON=$(echo "$P3_OUT" | tail -1)
P4_JSON=$(echo "$P4_OUT" | tail -1)
P5_JSON=$(echo "$P5_OUT" | tail -1)

# Check spam post - should be deleted/trashed
SPAM_EXISTS="true"
SPAM_ID=$(wp_db_query "SELECT ID FROM wp_posts
    WHERE LOWER(TRIM(post_title)) LIKE '%v1agra%'
    AND post_type='post'
    AND post_status NOT IN ('trash', 'auto-draft')
    ORDER BY ID DESC LIMIT 1")

if [ -z "$SPAM_ID" ]; then
    SPAM_EXISTS="false"
    echo "  SPAM post: deleted/trashed (GOOD)"
else
    SPAM_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$SPAM_ID")
    echo "  SPAM post (ID: $SPAM_ID): still exists with status=$SPAM_STATUS (BAD)"
fi

SPAM_DELETED="false"
if [ "$SPAM_EXISTS" = "false" ]; then
    SPAM_DELETED="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "posts": {
        "cloud_computing": $P1_JSON,
        "ai_development": $P2_JSON,
        "hiking_guide": $P3_JSON,
        "meal_prep": $P4_JSON,
        "business_awards": $P5_JSON
    },
    "spam_deleted": $SPAM_DELETED,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/audit_reorganize_content_result.json 2>/dev/null || sudo rm -f /tmp/audit_reorganize_content_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/audit_reorganize_content_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/audit_reorganize_content_result.json
chmod 666 /tmp/audit_reorganize_content_result.json 2>/dev/null || sudo chmod 666 /tmp/audit_reorganize_content_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/audit_reorganize_content_result.json"
cat /tmp/audit_reorganize_content_result.json
echo ""
echo "=== Export complete ==="
