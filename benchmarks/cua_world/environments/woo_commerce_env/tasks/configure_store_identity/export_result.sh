#!/bin/bash
# Export script for Configure Store Identity task

echo "=== Exporting Configure Store Identity Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. Retrieve Current Settings (wp_options)
# ==============================================================================
CURRENT_TITLE=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='blogname'")
CURRENT_TAGLINE=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='blogdescription'")
CURRENT_TIMEZONE=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='timezone_string'")
SHOW_ON_FRONT=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='show_on_front'")
PAGE_ON_FRONT_ID=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='page_on_front'")
PAGE_FOR_POSTS_ID=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='page_for_posts'")

# ==============================================================================
# 2. Retrieve Pages (wp_posts)
# ==============================================================================
# Find page titled "Home"
HOME_PAGE_DATA=$(wc_query "SELECT ID, post_status FROM wp_posts WHERE post_type='page' AND post_title='Home' AND post_status='publish' ORDER BY ID DESC LIMIT 1")
HOME_PAGE_ID=$(echo "$HOME_PAGE_DATA" | cut -f1)
HOME_PAGE_STATUS=$(echo "$HOME_PAGE_DATA" | cut -f2)

# Find page titled "News"
NEWS_PAGE_DATA=$(wc_query "SELECT ID, post_status FROM wp_posts WHERE post_type='page' AND post_title='News' AND post_status='publish' ORDER BY ID DESC LIMIT 1")
NEWS_PAGE_ID=$(echo "$NEWS_PAGE_DATA" | cut -f1)
NEWS_PAGE_STATUS=$(echo "$NEWS_PAGE_DATA" | cut -f2)

# ==============================================================================
# 3. Verify Assignments
# ==============================================================================
# Check if the assigned front page ID matches the created "Home" page ID
FRONT_PAGE_CORRECT="false"
if [ -n "$HOME_PAGE_ID" ] && [ "$PAGE_ON_FRONT_ID" == "$HOME_PAGE_ID" ]; then
    FRONT_PAGE_CORRECT="true"
fi

# Check if the assigned posts page ID matches the created "News" page ID
POSTS_PAGE_CORRECT="false"
if [ -n "$NEWS_PAGE_ID" ] && [ "$PAGE_FOR_POSTS_ID" == "$NEWS_PAGE_ID" ]; then
    POSTS_PAGE_CORRECT="true"
fi

# ==============================================================================
# 4. Generate JSON Output
# ==============================================================================
# Escape strings
CURRENT_TITLE_ESC=$(json_escape "$CURRENT_TITLE")
CURRENT_TAGLINE_ESC=$(json_escape "$CURRENT_TAGLINE")
CURRENT_TIMEZONE_ESC=$(json_escape "$CURRENT_TIMEZONE")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_title": "$CURRENT_TITLE_ESC",
    "tagline": "$CURRENT_TAGLINE_ESC",
    "timezone": "$CURRENT_TIMEZONE_ESC",
    "show_on_front": "$SHOW_ON_FRONT",
    "home_page_created": $([ -n "$HOME_PAGE_ID" ] && echo "true" || echo "false"),
    "home_page_id": "${HOME_PAGE_ID:-0}",
    "news_page_created": $([ -n "$NEWS_PAGE_ID" ] && echo "true" || echo "false"),
    "news_page_id": "${NEWS_PAGE_ID:-0}",
    "front_page_assigned_correctly": $FRONT_PAGE_CORRECT,
    "posts_page_assigned_correctly": $POSTS_PAGE_CORRECT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json