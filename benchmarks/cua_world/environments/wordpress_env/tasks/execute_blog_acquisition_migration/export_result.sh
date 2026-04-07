#!/bin/bash
# Export script for execute_blog_acquisition_migration task

echo "=== Exporting execute_blog_acquisition_migration result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# 1. Check User Creation
# ============================================================
USER_EXISTS="false"
USER_ROLE=""
USER_ID=""

USER_ID=$(wp user get cloudnova_archive --field=ID --allow-root 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
    USER_EXISTS="true"
    USER_ROLE=$(wp user get cloudnova_archive --field=roles --allow-root 2>/dev/null || echo "")
fi

# ============================================================
# 2. Check Data Imported & Author Mapping
# ============================================================
POSTS_IMPORTED="false"
AUTHORS_MAPPED_CORRECTLY="false"

# Look up the IDs of the 3 imported posts
POST1_ID=$(wp db query "SELECT ID FROM wp_posts WHERE post_title='Welcome to CloudNova' AND post_type='post' LIMIT 1" --skip-column-names --allow-root 2>/dev/null)
POST2_ID=$(wp db query "SELECT ID FROM wp_posts WHERE post_title='5 Tips for Cloud Security' AND post_type='post' LIMIT 1" --skip-column-names --allow-root 2>/dev/null)
POST3_ID=$(wp db query "SELECT ID FROM wp_posts WHERE post_title='Scaling Microservices Architecture' AND post_type='post' LIMIT 1" --skip-column-names --allow-root 2>/dev/null)

if [ -n "$POST1_ID" ] && [ -n "$POST2_ID" ] && [ -n "$POST3_ID" ]; then
    POSTS_IMPORTED="true"
    
    # Check if they belong to cloudnova_archive
    AUTHOR1=$(wp db query "SELECT post_author FROM wp_posts WHERE ID=$POST1_ID" --skip-column-names --allow-root)
    AUTHOR2=$(wp db query "SELECT post_author FROM wp_posts WHERE ID=$POST2_ID" --skip-column-names --allow-root)
    AUTHOR3=$(wp db query "SELECT post_author FROM wp_posts WHERE ID=$POST3_ID" --skip-column-names --allow-root)
    
    if [ "$AUTHOR1" = "$USER_ID" ] && [ "$AUTHOR2" = "$USER_ID" ] && [ "$AUTHOR3" = "$USER_ID" ]; then
        AUTHORS_MAPPED_CORRECTLY="true"
    fi
fi

# ============================================================
# 3. Check Category Assignment
# ============================================================
CATEGORY_EXISTS="false"
CATEGORY_APPLIED="false"
CATEGORY_ID=$(wp db query "SELECT term_id FROM wp_terms WHERE name='CloudNova Acquisition' LIMIT 1" --skip-column-names --allow-root 2>/dev/null)

if [ -n "$CATEGORY_ID" ]; then
    CATEGORY_EXISTS="true"
    
    if [ "$POSTS_IMPORTED" = "true" ]; then
        # Check if term is applied to all 3 posts
        CAT1_CHECK=$(wp db query "SELECT object_id FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$CATEGORY_ID AND object_id=$POST1_ID" --skip-column-names --allow-root)
        CAT2_CHECK=$(wp db query "SELECT object_id FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$CATEGORY_ID AND object_id=$POST2_ID" --skip-column-names --allow-root)
        CAT3_CHECK=$(wp db query "SELECT object_id FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$CATEGORY_ID AND object_id=$POST3_ID" --skip-column-names --allow-root)
        
        if [ -n "$CAT1_CHECK" ] && [ -n "$CAT2_CHECK" ] && [ -n "$CAT3_CHECK" ]; then
            CATEGORY_APPLIED="true"
        fi
    fi
fi

# ============================================================
# 4. Check Draft Purged (Must be 0 across ALL statuses)
# ============================================================
DRAFT_COUNT=$(wp db query "SELECT COUNT(*) FROM wp_posts WHERE post_title='Draft: Internal Q3 Strategy' AND post_type='post'" --skip-column-names --allow-root 2>/dev/null || echo "0")

# ============================================================
# 5. Check Sticky & Date
# ============================================================
WELCOME_IS_STICKY="false"
WELCOME_YEAR="2024"

if [ -n "$POST1_ID" ]; then
    # Check sticky array in options
    STICKY_POSTS=$(wp option get sticky_posts --format=json --allow-root 2>/dev/null || echo "[]")
    if echo "$STICKY_POSTS" | grep -q "\b$POST1_ID\b"; then
        WELCOME_IS_STICKY="true"
    fi
    
    # Check date
    POST_DATE=$(wp db query "SELECT post_date FROM wp_posts WHERE ID=$POST1_ID" --skip-column-names --allow-root)
    WELCOME_YEAR=$(echo "$POST_DATE" | cut -d'-' -f1)
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_exists": $USER_EXISTS,
    "user_role": "$(json_escape "$USER_ROLE")",
    "user_id": "$(json_escape "$USER_ID")",
    "posts_imported": $POSTS_IMPORTED,
    "authors_mapped_correctly": $AUTHORS_MAPPED_CORRECTLY,
    "category_exists": $CATEGORY_EXISTS,
    "category_applied": $CATEGORY_APPLIED,
    "draft_count": $DRAFT_COUNT,
    "welcome_is_sticky": $WELCOME_IS_STICKY,
    "welcome_year": "$WELCOME_YEAR",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="