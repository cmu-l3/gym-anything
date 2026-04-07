#!/bin/bash
# Export script for create_photo_portfolio task (post_task hook)

echo "=== Exporting create_photo_portfolio result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get baseline counts
INITIAL_ATTACHMENTS=$(cat /tmp/initial_attachments 2>/dev/null || echo "0")
INITIAL_PAGES=$(cat /tmp/initial_pages 2>/dev/null || echo "0")

# Get current counts
CURRENT_ATTACHMENTS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment' AND post_mime_type LIKE 'image/%'" 2>/dev/null || echo "0")
CURRENT_PAGES=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='page'" 2>/dev/null || echo "0")

echo "Attachments: $INITIAL_ATTACHMENTS -> $CURRENT_ATTACHMENTS"
echo "Pages: $INITIAL_PAGES -> $CURRENT_PAGES"

# 1. Check for the 5 uploaded images and their alt text
IMAGES=(
    "city-skyline.jpg"
    "street-market.jpg"
    "bridge-sunset.jpg"
    "historic-building.jpg"
    "park-fountain.jpg"
)

UPLOADED_IMAGES_JSON="["
FIRST_IMG=true

for filename in "${IMAGES[@]}"; do
    # Search for attachment by guid containing the filename
    ATTACH_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='attachment' AND guid LIKE '%$filename%' ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    
    FOUND="false"
    ALT_TEXT=""
    
    if [ -n "$ATTACH_ID" ]; then
        FOUND="true"
        # Get alt text
        ALT_TEXT=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ATTACH_ID AND meta_key='_wp_attachment_image_alt' LIMIT 1" 2>/dev/null)
        echo "Found image $filename (ID: $ATTACH_ID), Alt: '$ALT_TEXT'"
    else
        echo "Image $filename NOT found"
    fi
    
    # Append to JSON array
    if [ "$FIRST_IMG" = true ]; then
        FIRST_IMG=false
    else
        UPLOADED_IMAGES_JSON+=","
    fi
    
    ESCAPED_ALT=$(echo "$ALT_TEXT" | sed 's/"/\\"/g' | tr -d '\n')
    UPLOADED_IMAGES_JSON+="{\"filename\": \"$filename\", \"found\": $FOUND, \"alt_text\": \"$ESCAPED_ALT\", \"id\": \"$ATTACH_ID\"}"
done
UPLOADED_IMAGES_JSON+="]"

# 2. Check for the Portfolio Page
PAGE_TITLE="Urban Photography Portfolio"
PAGE_FOUND="false"
PAGE_ID=""
PAGE_STATUS=""
PAGE_CONTENT=""

# Search for the page by exact title
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$PAGE_TITLE')) AND post_type='page' ORDER BY ID DESC LIMIT 1" 2>/dev/null)

if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
    PAGE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
    echo "Found page '$PAGE_TITLE' (ID: $PAGE_ID), Status: $PAGE_STATUS"
else
    # Fallback: check if they created any new page
    echo "Page '$PAGE_TITLE' NOT found by exact title."
    # Let the verifier decide partial credit if a new page was made but title was slightly wrong
    PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND ID > $INITIAL_PAGES ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PAGE_ID" ]; then
        PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
        PAGE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
        ACTUAL_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
        echo "Found alternative new page: '$ACTUAL_TITLE' (ID: $PAGE_ID)"
    fi
fi

ESCAPED_CONTENT=$(echo "$PAGE_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 10000)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "counts": {
        "initial_attachments": $INITIAL_ATTACHMENTS,
        "current_attachments": $CURRENT_ATTACHMENTS,
        "initial_pages": $INITIAL_PAGES,
        "current_pages": $CURRENT_PAGES
    },
    "images": $UPLOADED_IMAGES_JSON,
    "page": {
        "found": $PAGE_FOUND,
        "id": "${PAGE_ID:-}",
        "status": "${PAGE_STATUS:-}",
        "content": "$ESCAPED_CONTENT"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="