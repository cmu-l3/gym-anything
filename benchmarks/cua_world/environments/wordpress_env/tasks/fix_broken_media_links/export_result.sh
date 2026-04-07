#!/bin/bash
# Export script for fix_broken_media_links task

echo "=== Exporting fix_broken_media_links result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TARGET_POST_ID=$(cat /tmp/target_post_id 2>/dev/null || echo "")

# Initialize variables
GUGGENHEIM_ID=""
GUGGENHEIM_ALT=""
BAUHAUS_ID=""
BAUHAUS_ALT=""
FALLINGWATER_ID=""
FALLINGWATER_ALT=""
POST_CONTENT=""
LEGACY_URL_COUNT=0
NEW_UPLOAD_COUNT=0
PHYSICAL_FILES_COUNT=0

# ============================================================
# 1. Check Media Library (wp_posts & wp_postmeta)
# ============================================================
get_attachment_data() {
    local keyword="$1"
    local id_var="$2"
    local alt_var="$3"
    
    # Find attachment ID
    local att_id=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='attachment' AND (post_title LIKE '%${keyword}%' OR guid LIKE '%${keyword}%') ORDER BY ID DESC LIMIT 1")
    
    if [ -n "$att_id" ]; then
        eval "$id_var=\"$att_id\""
        # Get alt text from postmeta
        local alt_text=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$att_id AND meta_key='_wp_attachment_image_alt' LIMIT 1")
        eval "$alt_var=\"$(echo "$alt_text" | sed 's/"/\\"/g' | tr -d '\n')\""
        echo "Found attachment '$keyword' (ID: $att_id), Alt: '$alt_text'"
    else
        eval "$id_var=\"\""
        eval "$alt_var=\"\""
        echo "Attachment '$keyword' NOT found"
    fi
}

get_attachment_data "guggenheim" "GUGGENHEIM_ID" "GUGGENHEIM_ALT"
get_attachment_data "bauhaus" "BAUHAUS_ID" "BAUHAUS_ALT"
get_attachment_data "fallingwater" "FALLINGWATER_ID" "FALLINGWATER_ALT"

# ============================================================
# 2. Check Physical Files in wp-content/uploads
# ============================================================
# Check files modified/created after task start time
UPLOADS_DIR="/var/www/html/wordpress/wp-content/uploads"
if [ -d "$UPLOADS_DIR" ]; then
    PHYSICAL_FILES_COUNT=$(find "$UPLOADS_DIR" -type f -name "*.jpg" -newermt "@$TASK_START" 2>/dev/null | wc -l)
    echo "Physical new .jpg files in uploads: $PHYSICAL_FILES_COUNT"
fi

# ============================================================
# 3. Check Target Post Content
# ============================================================
if [ -z "$TARGET_POST_ID" ]; then
    # Fallback to finding it by title if ID is lost
    TARGET_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Exploring Modern Architecture Masterpieces' AND post_type='post' ORDER BY ID DESC LIMIT 1")
fi

if [ -n "$TARGET_POST_ID" ]; then
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$TARGET_POST_ID")
    
    # Count occurrences of legacy domain
    LEGACY_URL_COUNT=$(echo "$POST_CONTENT" | grep -o -i "legacy-site.local" | wc -l)
    
    # Count occurrences of valid local uploads (attachment references or wp-content paths)
    NEW_UPLOAD_COUNT=$(echo "$POST_CONTENT" | grep -o -i "wp-content/uploads" | wc -l)
    
    echo "Legacy URL count in post: $LEGACY_URL_COUNT"
    echo "New upload path count in post: $NEW_UPLOAD_COUNT"
else
    echo "Target post not found!"
fi

# Escape content for JSON
ESCAPED_CONTENT=$(echo "$POST_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 5000)

# ============================================================
# 4. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "attachments": {
        "guggenheim": {
            "found": $([ -n "$GUGGENHEIM_ID" ] && echo "true" || echo "false"),
            "id": "$GUGGENHEIM_ID",
            "alt_text": "$GUGGENHEIM_ALT"
        },
        "bauhaus": {
            "found": $([ -n "$BAUHAUS_ID" ] && echo "true" || echo "false"),
            "id": "$BAUHAUS_ID",
            "alt_text": "$BAUHAUS_ALT"
        },
        "fallingwater": {
            "found": $([ -n "$FALLINGWATER_ID" ] && echo "true" || echo "false"),
            "id": "$FALLINGWATER_ID",
            "alt_text": "$FALLINGWATER_ALT"
        }
    },
    "physical_files_count": $PHYSICAL_FILES_COUNT,
    "target_post": {
        "id": "$TARGET_POST_ID",
        "legacy_url_count": $LEGACY_URL_COUNT,
        "new_upload_count": $NEW_UPLOAD_COUNT,
        "content_excerpt": "$ESCAPED_CONTENT"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/fix_broken_media_links_result.json 2>/dev/null || sudo rm -f /tmp/fix_broken_media_links_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fix_broken_media_links_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fix_broken_media_links_result.json
chmod 666 /tmp/fix_broken_media_links_result.json 2>/dev/null || sudo chmod 666 /tmp/fix_broken_media_links_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/fix_broken_media_links_result.json"
cat /tmp/fix_broken_media_links_result.json
echo ""
echo "=== Export complete ==="