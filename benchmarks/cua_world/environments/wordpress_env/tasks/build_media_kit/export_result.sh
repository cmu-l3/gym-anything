#!/bin/bash
# Export script for build_media_kit task (post_task hook)

echo "=== Exporting build_media_kit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Get initial counts
INITIAL_ATTACHMENTS=$(cat /tmp/initial_attachment_count 2>/dev/null || echo "0")
CURRENT_ATTACHMENTS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment'")

# Find attachments and their direct URLs (GUIDs)
PDF_GUID=$(wp_db_query "SELECT guid FROM wp_posts WHERE post_type='attachment' AND post_mime_type='application/pdf' AND (post_title LIKE '%Nimbus_Press_Release%' OR post_name LIKE '%nimbus_press_release%') ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')
ZIP_GUID=$(wp_db_query "SELECT guid FROM wp_posts WHERE post_type='attachment' AND post_mime_type='application/zip' AND (post_title LIKE '%Nimbus_Brand_Assets%' OR post_name LIKE '%nimbus_brand_assets%') ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')
JPG_GUID=$(wp_db_query "SELECT guid FROM wp_posts WHERE post_type='attachment' AND post_mime_type='image/jpeg' AND (post_title LIKE '%CEO_Portrait%' OR post_name LIKE '%ceo_portrait%') ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')

# Find the target page
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_status='publish' AND LOWER(post_title)='official media kit' ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')

PAGE_CONTENT_B64=""
PAGE_STATUS=""

if [ -n "$PAGE_ID" ]; then
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID" | tr -d '\r\n')
    PAGE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID")
    # Base64 encode the content to completely avoid JSON escaping nightmares in Bash
    PAGE_CONTENT_B64=$(echo -n "$PAGE_CONTENT" | base64 -w 0)
fi

echo "Attachments Found:"
echo "  PDF: ${PDF_GUID:-Not found}"
echo "  ZIP: ${ZIP_GUID:-Not found}"
echo "  JPG: ${JPG_GUID:-Not found}"
echo "Page ID: ${PAGE_ID:-Not found}"

# Safely construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_attachments": $INITIAL_ATTACHMENTS,
    "current_attachments": $CURRENT_ATTACHMENTS,
    "pdf_guid": "$PDF_GUID",
    "zip_guid": "$ZIP_GUID",
    "jpg_guid": "$JPG_GUID",
    "page_id": "$PAGE_ID",
    "page_status": "$PAGE_STATUS",
    "page_content_b64": "$PAGE_CONTENT_B64",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/build_media_kit_result.json 2>/dev/null || sudo rm -f /tmp/build_media_kit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_media_kit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/build_media_kit_result.json
chmod 666 /tmp/build_media_kit_result.json 2>/dev/null || sudo chmod 666 /tmp/build_media_kit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="