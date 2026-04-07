#!/bin/bash
# Export script for reorganize_taxonomy task (post_task hook)
# Collects the state of the WordPress taxonomy for verification

echo "=== Exporting reorganize_taxonomy result ==="

source /workspace/scripts/task_utils.sh
cd /var/www/html/wordpress

take_screenshot /tmp/task_final.png

# 1. Check if 'Technology' exists and 'Techology' is gone
TECH_EXISTS="false"
[ "$(wp term list category --name="Technology" --format=count --allow-root 2>/dev/null)" -gt 0 ] && TECH_EXISTS="true"

TYPO_EXISTS="false"
[ "$(wp term list category --name="Techology" --format=count --allow-root 2>/dev/null)" -gt 0 ] && TYPO_EXISTS="true"

# 2. Check if 'Miscellaneous Stuff' is deleted
MISC_EXISTS="false"
[ "$(wp term list category --name="Miscellaneous Stuff" --format=count --allow-root 2>/dev/null)" -gt 0 ] && MISC_EXISTS="true"

# 3. Check if 'Content Hub' exists and is top-level
HUB_EXISTS="false"
HUB_IS_TOP_LEVEL="false"
HUB_ID=$(wp term list category --name="Content Hub" --field=term_id --allow-root 2>/dev/null)

if [ -n "$HUB_ID" ]; then
    HUB_EXISTS="true"
    HUB_PARENT=$(wp term get category "$HUB_ID" --field=parent --allow-root 2>/dev/null)
    if [ "$HUB_PARENT" = "0" ]; then
        HUB_IS_TOP_LEVEL="true"
    fi
fi

# 4. Check hierarchy (Technology, Travel, Lifestyle as children of Content Hub)
TECH_IS_CHILD="false"
TRAVEL_IS_CHILD="false"
LIFESTYLE_IS_CHILD="false"

if [ -n "$HUB_ID" ]; then
    TECH_PARENT=$(wp term list category --name="Technology" --field=parent --allow-root 2>/dev/null || echo "")
    if [ "$TECH_PARENT" = "$HUB_ID" ]; then TECH_IS_CHILD="true"; fi

    TRAVEL_PARENT=$(wp term list category --name="Travel" --field=parent --allow-root 2>/dev/null || echo "")
    if [ "$TRAVEL_PARENT" = "$HUB_ID" ]; then TRAVEL_IS_CHILD="true"; fi

    LIFESTYLE_PARENT=$(wp term list category --name="Lifestyle" --field=parent --allow-root 2>/dev/null || echo "")
    if [ "$LIFESTYLE_PARENT" = "$HUB_ID" ]; then LIFESTYLE_IS_CHILD="true"; fi
fi

# 5. Check if unused tag is deleted
DRAFT_TAG_EXISTS="false"
[ "$(wp term list post_tag --name="temp-draft-marker" --format=count --allow-root 2>/dev/null)" -gt 0 ] && DRAFT_TAG_EXISTS="true"

# 6. Check if the 3 most recent posts have the 'featured' tag
RECENT_POSTS_TAGGED=0
TOTAL_RECENT_POSTS=0

if [ -f /tmp/recent_post_ids.txt ]; then
    while read -r POST_ID; do
        if [ -n "$POST_ID" ]; then
            TOTAL_RECENT_POSTS=$((TOTAL_RECENT_POSTS + 1))
            # Get tags for the post, check if 'featured' is among them
            if wp post term list "$POST_ID" post_tag --field=name --allow-root 2>/dev/null | grep -iqw "featured"; then
                RECENT_POSTS_TAGGED=$((RECENT_POSTS_TAGGED + 1))
            fi
        fi
    done < /tmp/recent_post_ids.txt
fi

ALL_RECENT_TAGGED="false"
if [ "$TOTAL_RECENT_POSTS" -gt 0 ] && [ "$RECENT_POSTS_TAGGED" -eq "$TOTAL_RECENT_POSTS" ]; then
    ALL_RECENT_TAGGED="true"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tech_exists": $TECH_EXISTS,
    "typo_exists": $TYPO_EXISTS,
    "misc_exists": $MISC_EXISTS,
    "hub_exists": $HUB_EXISTS,
    "hub_is_top_level": $HUB_IS_TOP_LEVEL,
    "tech_is_child": $TECH_IS_CHILD,
    "travel_is_child": $TRAVEL_IS_CHILD,
    "lifestyle_is_child": $LIFESTYLE_IS_CHILD,
    "draft_tag_exists": $DRAFT_TAG_EXISTS,
    "all_recent_tagged": $ALL_RECENT_TAGGED,
    "recent_posts_tagged_count": $RECENT_POSTS_TAGGED,
    "total_recent_posts": $TOTAL_RECENT_POSTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/reorganize_taxonomy_result.json 2>/dev/null || sudo rm -f /tmp/reorganize_taxonomy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/reorganize_taxonomy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/reorganize_taxonomy_result.json
chmod 666 /tmp/reorganize_taxonomy_result.json 2>/dev/null || sudo chmod 666 /tmp/reorganize_taxonomy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/reorganize_taxonomy_result.json"
cat /tmp/reorganize_taxonomy_result.json
echo "=== Export complete ==="