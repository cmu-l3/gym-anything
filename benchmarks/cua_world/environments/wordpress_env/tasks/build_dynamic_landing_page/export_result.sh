#!/bin/bash
# Export script for build_dynamic_landing_page task
echo "=== Exporting build_dynamic_landing_page result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

TRAVEL_CAT_ID=$(cat /tmp/travel_category_id 2>/dev/null || echo "0")
PAGE_FOUND="false"
PAGE_ID=""
PAGE_STATUS=""
PAGE_CONTENT_B64=""
PAGE_CREATED_TIME="0"

# Find the page created by the agent
echo "Checking for 'Summer Explorer Campaign' page..."
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Summer Explorer Campaign') AND post_type='page' ORDER BY ID DESC LIMIT 1")

if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_DATE=$(wp_db_query "SELECT post_date FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_CREATED_TIME=$(date -d "$PAGE_DATE" +%s 2>/dev/null || echo "0")
    
    # Extract content as base64 to avoid all JSON escaping nightmares with HTML/Gutenberg comments
    PAGE_CONTENT_B64=$(docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -N -e "SELECT TO_BASE64(post_content) FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null | tr -d '\n' | tr -d ' ')
    echo "Page found with ID: $PAGE_ID"
else
    echo "Page not found."
fi

# Check if media was uploaded
MEDIA_FOUND="false"
MEDIA_COUNT=$(find /var/www/html/wordpress/wp-content/uploads -type f -name "*hero_mountain*" 2>/dev/null | wc -l)
if [ "$MEDIA_COUNT" -gt 0 ]; then
    MEDIA_FOUND="true"
    echo "Uploaded media found."
fi

# Check frontend settings
SHOW_ON_FRONT=$(wp_cli option get show_on_front 2>/dev/null || echo "posts")
PAGE_ON_FRONT=$(wp_cli option get page_on_front 2>/dev/null || echo "0")

echo "Frontend routing: show_on_front='$SHOW_ON_FRONT', page_on_front='$PAGE_ON_FRONT'"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "travel_category_id": "$TRAVEL_CAT_ID",
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-0}",
    "page_status": "$PAGE_STATUS",
    "page_created_timestamp": $PAGE_CREATED_TIME,
    "page_content_b64": "$PAGE_CONTENT_B64",
    "media_uploaded": $MEDIA_FOUND,
    "show_on_front": "$SHOW_ON_FRONT",
    "page_on_front": "$PAGE_ON_FRONT",
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/build_dynamic_landing_page_result.json 2>/dev/null || sudo rm -f /tmp/build_dynamic_landing_page_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_dynamic_landing_page_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/build_dynamic_landing_page_result.json
chmod 666 /tmp/build_dynamic_landing_page_result.json 2>/dev/null || sudo chmod 666 /tmp/build_dynamic_landing_page_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/build_dynamic_landing_page_result.json"
echo "=== Export complete ==="