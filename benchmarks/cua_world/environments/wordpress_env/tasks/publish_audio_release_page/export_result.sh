#!/bin/bash
# Export script for publish_audio_release_page task
# Gathers verification data (page content, media library counts) and exports to JSON

echo "=== Exporting publish_audio_release_page result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get start time for anti-gaming (checking for new attachments)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ============================================================
# Search for the Page
# ============================================================
PAGE_FOUND="false"
PAGE_ID=""
PAGE_STATUS=""
PAGE_TYPE=""
PAGE_CONTENT=""

# Try exact title match first
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Classical Sessions EP') AND post_type='page' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

# If not found, broaden search to any status or post type
if [ -z "$PAGE_ID" ]; then
    PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Classical Sessions EP') ORDER BY ID DESC LIMIT 1")
fi

if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_TYPE=$(wp_db_query "SELECT post_type FROM wp_posts WHERE ID=$PAGE_ID")
    
    # Safely extract post content using Python to completely avoid bash escaping issues
    wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID" > /tmp/raw_content.txt
    PAGE_CONTENT=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().strip()))' < /tmp/raw_content.txt)
    echo "Found page ID: $PAGE_ID (Status: $PAGE_STATUS, Type: $PAGE_TYPE)"
else
    echo "Page 'Classical Sessions EP' not found"
    PAGE_CONTENT='""'
fi

# ============================================================
# Check Media Library for Newly Uploaded Assets
# ============================================================
NEW_AUDIO_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment' AND post_mime_type LIKE 'audio/%' AND UNIX_TIMESTAMP(post_date) >= $TASK_START" 2>/dev/null || echo "0")
NEW_IMAGE_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment' AND post_mime_type LIKE 'image/%' AND UNIX_TIMESTAMP(post_date) >= $TASK_START" 2>/dev/null || echo "0")

echo "Newly uploaded audio files: $NEW_AUDIO_COUNT"
echo "Newly uploaded image files: $NEW_IMAGE_COUNT"

# ============================================================
# Generate Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "page_status": "${PAGE_STATUS:-}",
    "page_type": "${PAGE_TYPE:-}",
    "post_content": $PAGE_CONTENT,
    "new_audio_count": ${NEW_AUDIO_COUNT:-0},
    "new_image_count": ${NEW_IMAGE_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location securely
rm -f /tmp/publish_audio_release_result.json 2>/dev/null || sudo rm -f /tmp/publish_audio_release_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/publish_audio_release_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/publish_audio_release_result.json
chmod 666 /tmp/publish_audio_release_result.json 2>/dev/null || sudo chmod 666 /tmp/publish_audio_release_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/publish_audio_release_result.json"
echo "=== Export complete ==="