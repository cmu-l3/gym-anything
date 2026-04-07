#!/bin/bash
# Export script for configure_static_homepage task (post_task hook)

echo "=== Exporting configure_static_homepage result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Get WordPress Reading Options
SHOW_ON_FRONT=$(wp option get show_on_front --allow-root 2>/dev/null || echo "posts")
PAGE_ON_FRONT=$(wp option get page_on_front --allow-root 2>/dev/null || echo "0")
PAGE_FOR_POSTS=$(wp option get page_for_posts --allow-root 2>/dev/null || echo "0")

echo "Reading Settings:"
echo "  show_on_front: $SHOW_ON_FRONT"
echo "  page_on_front: $PAGE_ON_FRONT"
echo "  page_for_posts: $PAGE_FOR_POSTS"

# 2. Check if the Portfolio page exists and get its details
PORTFOLIO_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_status='publish' AND LOWER(TRIM(post_title)) = 'portfolio' ORDER BY ID DESC LIMIT 1")
PORTFOLIO_FOUND="false"
PORTFOLIO_CONTENT=""
PORTFOLIO_CREATED=""

if [ -n "$PORTFOLIO_ID" ]; then
    PORTFOLIO_FOUND="true"
    PORTFOLIO_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PORTFOLIO_ID")
    PORTFOLIO_CREATED=$(wp_db_query "SELECT UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE ID=$PORTFOLIO_ID")
    echo "Found Portfolio page: ID $PORTFOLIO_ID"
else
    echo "Portfolio page NOT found"
fi

# 3. Check if the Journal page exists and get its details
JOURNAL_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_status='publish' AND LOWER(TRIM(post_title)) = 'journal' ORDER BY ID DESC LIMIT 1")
JOURNAL_FOUND="false"
JOURNAL_CONTENT=""
JOURNAL_CREATED=""

if [ -n "$JOURNAL_ID" ]; then
    JOURNAL_FOUND="true"
    JOURNAL_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$JOURNAL_ID")
    JOURNAL_CREATED=$(wp_db_query "SELECT UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE ID=$JOURNAL_ID")
    echo "Found Journal page: ID $JOURNAL_ID"
else
    echo "Journal page NOT found"
fi

# 4. Do an HTTP request to the front page to see what's actually served
FRONT_PAGE_HTML=$(curl -sL http://localhost/ | head -c 10000 | tr -d '\n' | sed 's/"/\\"/g')

# Escape content for JSON safely
PORTFOLIO_CONTENT_ESC=$(echo "$PORTFOLIO_CONTENT" | tr -d '\n' | sed 's/"/\\"/g' | head -c 5000)
JOURNAL_CONTENT_ESC=$(echo "$JOURNAL_CONTENT" | tr -d '\n' | sed 's/"/\\"/g' | head -c 5000)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "settings": {
        "show_on_front": "$SHOW_ON_FRONT",
        "page_on_front": "$PAGE_ON_FRONT",
        "page_for_posts": "$PAGE_FOR_POSTS"
    },
    "portfolio": {
        "found": $PORTFOLIO_FOUND,
        "id": "${PORTFOLIO_ID:-0}",
        "content": "$PORTFOLIO_CONTENT_ESC",
        "created_ts": ${PORTFOLIO_CREATED:-0}
    },
    "journal": {
        "found": $JOURNAL_FOUND,
        "id": "${JOURNAL_ID:-0}",
        "content": "$JOURNAL_CONTENT_ESC",
        "created_ts": ${JOURNAL_CREATED:-0}
    },
    "front_page_html": "$FRONT_PAGE_HTML",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="