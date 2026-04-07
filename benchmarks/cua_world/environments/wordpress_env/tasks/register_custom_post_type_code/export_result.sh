#!/bin/bash
echo "=== Exporting Custom Post Type task result ==="

source /workspace/scripts/task_utils.sh
cd /var/www/html/wordpress

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Check HTTP Health (detects fatal PHP errors)
# ============================================================
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
echo "HTTP Status: $HTTP_CODE"

# ============================================================
# 2. Check File Modification
# ============================================================
FUNCTIONS_PATH="/var/www/html/wordpress/wp-content/themes/agency-child/functions.php"
INITIAL_MTIME=$(cat /tmp/functions_initial_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME=$(stat -c %Y "$FUNCTIONS_PATH" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
fi
echo "functions.php modified: $FILE_MODIFIED"

# ============================================================
# 3. Check Installed Plugins (Anti-Gaming)
# ============================================================
# Find if any CPT plugins were installed/activated
PLUGINS=$(wp plugin list --status=active --field=name --allow-root 2>/dev/null | tr '\n' ',' || echo "")
echo "Active plugins: $PLUGINS"

# ============================================================
# 4. Extract CPT Configuration via WP-CLI + PHP
# ============================================================
wp eval '
$cpt = get_post_type_object("portfolio");
if ($cpt) {
    $data = array(
        "exists" => true,
        "public" => $cpt->public,
        "has_archive" => $cpt->has_archive,
        "show_in_rest" => $cpt->show_in_rest,
        "supports" => get_all_post_type_supports("portfolio")
    );
    echo json_encode($data);
} else {
    echo json_encode(array("exists" => false));
}
' --allow-root 2>/dev/null > /tmp/cpt_config.json

CPT_EXISTS=$(jq -r '.exists' /tmp/cpt_config.json)
echo "CPT Config Extracted. Exists: $CPT_EXISTS"

# ============================================================
# 5. Extract Portfolio Post Data
# ============================================================
POST_FOUND="false"
POST_ID=""
POST_TITLE=""
POST_EXCERPT=""
POST_CONTENT=""
THUMBNAIL_ID=""

if [ "$HTTP_CODE" = "200" ]; then
    # Try to find the specific post
    POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='portfolio' AND post_status='publish' AND LOWER(post_title) LIKE '%nasa%' ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$POST_ID" ]; then
        POST_FOUND="true"
        POST_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$POST_ID")
        POST_EXCERPT=$(wp_db_query "SELECT post_excerpt FROM wp_posts WHERE ID=$POST_ID")
        POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID")
        
        # Check for featured image (thumbnail)
        THUMBNAIL_ID=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$POST_ID AND meta_key='_thumbnail_id' LIMIT 1")
        
        echo "Found Post ID: $POST_ID"
        echo "Thumbnail ID: $THUMBNAIL_ID"
    else
        echo "Post not found."
    fi
fi

# Escape content for JSON safety
ESCAPED_TITLE=$(echo "$POST_TITLE" | sed 's/"/\\"/g' | tr -d '\n')
ESCAPED_EXCERPT=$(echo "$POST_EXCERPT" | sed 's/"/\\"/g' | tr -d '\n')
ESCAPED_CONTENT=$(echo "$POST_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 1000)

# ============================================================
# 6. Generate Final Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "http_status": "$HTTP_CODE",
    "file_modified_during_task": $FILE_MODIFIED,
    "active_plugins": "$PLUGINS",
    "cpt_config": $(cat /tmp/cpt_config.json),
    "post_data": {
        "found": $POST_FOUND,
        "id": "${POST_ID:-0}",
        "title": "$ESCAPED_TITLE",
        "excerpt": "$ESCAPED_EXCERPT",
        "content_length": ${#POST_CONTENT},
        "content_snippet": "$ESCAPED_CONTENT",
        "thumbnail_id": "${THUMBNAIL_ID:-0}"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/cpt_task_result.json 2>/dev/null || sudo rm -f /tmp/cpt_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cpt_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cpt_task_result.json
chmod 666 /tmp/cpt_task_result.json 2>/dev/null || sudo chmod 666 /tmp/cpt_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete, saved to /tmp/cpt_task_result.json"