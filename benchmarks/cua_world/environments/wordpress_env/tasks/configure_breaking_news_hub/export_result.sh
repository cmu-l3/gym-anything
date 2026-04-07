#!/bin/bash
# Export script for configure_breaking_news_hub task

echo "=== Exporting breaking_news_hub result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Get Tagline
CURRENT_TAGLINE=$(wp option get blogdescription --allow-root 2>/dev/null)

# 2. Get Category Info
CAT_NAME=$(wp_db_query "SELECT t.name FROM wp_terms t INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='category' AND LOWER(t.name)='breaking news' LIMIT 1")
CAT_SLUG=$(wp_db_query "SELECT t.slug FROM wp_terms t INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='category' AND LOWER(t.slug)='breaking-news' LIMIT 1")

# 3. Get Post Info
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='City Hall Election 2026: Live Results' AND post_type='post' LIMIT 1")
POST_STATUS=""
if [ -n "$POST_ID" ]; then
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID")
fi

# 4. Get Sticky Posts Array
STICKY_POSTS=$(wp option get sticky_posts --allow-root 2>/dev/null || echo "[]")

# 5. Get Menu Item Info
MENU_ITEM_ID=""
MENU_CLASSES=""
if [ -n "$POST_ID" ]; then
    # Find the menu item linking to our post
    MENU_ITEM_ID=$(wp_db_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_menu_item_object_id' AND meta_value='$POST_ID' LIMIT 1")
    
    # If a menu item was found, check its CSS classes
    if [ -n "$MENU_ITEM_ID" ]; then
        MENU_CLASSES=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id='$MENU_ITEM_ID' AND meta_key='_menu_item_classes' LIMIT 1")
    fi
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tagline": "$(json_escape "$CURRENT_TAGLINE")",
    "cat_name": "$(json_escape "$CAT_NAME")",
    "cat_slug": "$(json_escape "$CAT_SLUG")",
    "post_id": "${POST_ID:-}",
    "post_status": "${POST_STATUS:-}",
    "sticky_posts": "$(json_escape "$STICKY_POSTS")",
    "menu_item_id": "${MENU_ITEM_ID:-}",
    "menu_classes": "$(json_escape "$MENU_CLASSES")",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/configure_breaking_news_hub_result.json 2>/dev/null || sudo rm -f /tmp/configure_breaking_news_hub_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_breaking_news_hub_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_breaking_news_hub_result.json
chmod 666 /tmp/configure_breaking_news_hub_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_breaking_news_hub_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/configure_breaking_news_hub_result.json"
cat /tmp/configure_breaking_news_hub_result.json
echo "=== Export complete ==="