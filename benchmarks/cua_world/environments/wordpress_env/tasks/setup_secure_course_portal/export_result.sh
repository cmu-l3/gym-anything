#!/bin/bash
# Export script for setup_secure_course_portal task (post_task hook)

echo "=== Exporting Secure Course Portal Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initial counts
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
CURRENT_PAGE_COUNT=$(get_post_count "page" "publish")

# Check Parent Page
PARENT_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = 'history course portal' AND post_type='page' AND post_status='publish' LIMIT 1")
PARENT_EXISTS="false"
if [ -n "$PARENT_ID" ]; then
    PARENT_EXISTS="true"
    echo "Found Parent Page ID: $PARENT_ID"
else
    echo "Parent Page 'History Course Portal' not found."
fi

# Check Child Page
CHILD_EXISTS="false"
CHILD_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = 'apollo 11 & 12 documents' AND post_type='page' AND post_status='publish' LIMIT 1")

# Fallback check if slight typo in child title
if [ -z "$CHILD_ID" ]; then
    CHILD_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(post_title) LIKE '%apollo%' AND post_type='page' AND post_status='publish' ORDER BY ID DESC LIMIT 1")
fi

CHILD_PARENT_ID="0"
CHILD_PASSWORD=""
CHILD_COMMENTS=""
CHILD_CONTENT=""
THUMB_EXISTS="false"
THUMB_NAME=""

if [ -n "$CHILD_ID" ]; then
    CHILD_EXISTS="true"
    echo "Found Child Page ID: $CHILD_ID"
    
    # Extract metadata
    CHILD_PARENT_ID=$(wp_db_query "SELECT post_parent FROM wp_posts WHERE ID=$CHILD_ID")
    CHILD_PASSWORD=$(wp_db_query "SELECT post_password FROM wp_posts WHERE ID=$CHILD_ID")
    CHILD_COMMENTS=$(wp_db_query "SELECT comment_status FROM wp_posts WHERE ID=$CHILD_ID")
    CHILD_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$CHILD_ID")
    
    # Check Featured Image
    THUMB_ID=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$CHILD_ID AND meta_key='_thumbnail_id' LIMIT 1")
    if [ -n "$THUMB_ID" ] && [ "$THUMB_ID" != "NULL" ]; then
        THUMB_EXISTS="true"
        THUMB_NAME=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$THUMB_ID")
    fi
else
    echo "Child Page 'Apollo 11 & 12 Documents' not found."
fi

# Check Uploaded PDFs and Sizes
PDFS_UPLOADED=0
LARGE_PDFS=0
PDF_LINKS_IN_CONTENT="false"

ATTACHMENTS=$(wp_db_query "SELECT ID, post_title FROM wp_posts WHERE post_type='attachment' AND post_mime_type='application/pdf'")
if [ -n "$ATTACHMENTS" ]; then
    PDFS_UPLOADED=$(echo "$ATTACHMENTS" | grep -v "^$" | wc -l)
    
    # Verify sizes for anti-gaming (> 500KB)
    for id in $(echo "$ATTACHMENTS" | cut -f1); do
        FILE_REL_PATH=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$id AND meta_key='_wp_attached_file' LIMIT 1")
        FILE_ABS_PATH="/var/www/html/wordpress/wp-content/uploads/$FILE_REL_PATH"
        
        if [ -f "$FILE_ABS_PATH" ]; then
            SIZE=$(stat -c%s "$FILE_ABS_PATH" 2>/dev/null || echo "0")
            if [ "$SIZE" -gt 500000 ]; then
                LARGE_PDFS=$((LARGE_PDFS + 1))
            fi
        fi
    done
fi

# Check if content has links to pdfs or file blocks
if echo "$CHILD_CONTENT" | grep -qi "\.pdf"; then
    PDF_LINKS_IN_CONTENT="true"
elif echo "$CHILD_CONTENT" | grep -qi "wp:file"; then
    PDF_LINKS_IN_CONTENT="true"
fi

# Escape content for JSON
ESCAPED_CHILD_CONTENT=$(echo "$CHILD_CONTENT" | tr '\n' ' ' | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | head -c 5000)

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_page_count": $INITIAL_PAGE_COUNT,
    "current_page_count": $CURRENT_PAGE_COUNT,
    "parent_page": {
        "exists": $PARENT_EXISTS,
        "id": "${PARENT_ID:-}"
    },
    "child_page": {
        "exists": $CHILD_EXISTS,
        "id": "${CHILD_ID:-}",
        "parent_id": "${CHILD_PARENT_ID:-0}",
        "password": "$(echo "$CHILD_PASSWORD" | sed 's/"/\\"/g')",
        "comment_status": "$CHILD_COMMENTS",
        "has_thumbnail": $THUMB_EXISTS,
        "thumbnail_name": "$(echo "$THUMB_NAME" | sed 's/"/\\"/g')",
        "content_links_pdf": $PDF_LINKS_IN_CONTENT
    },
    "media": {
        "pdfs_uploaded_count": $PDFS_UPLOADED,
        "large_pdfs_count": $LARGE_PDFS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure safe copy
rm -f /tmp/setup_secure_course_portal_result.json 2>/dev/null || sudo rm -f /tmp/setup_secure_course_portal_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/setup_secure_course_portal_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/setup_secure_course_portal_result.json
chmod 666 /tmp/setup_secure_course_portal_result.json 2>/dev/null || sudo chmod 666 /tmp/setup_secure_course_portal_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/setup_secure_course_portal_result.json
echo "=== Export complete ==="