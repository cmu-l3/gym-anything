#!/bin/bash
# Export script for edit_media_natively_and_scale task (post_task hook)
# Uses WP-CLI and python to securely construct a JSON payload with verification data.

echo "=== Exporting edit_media_natively_and_scale result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Load injected IDs
export LANDSCAPE_ID=$(cat /tmp/landscape_id.txt 2>/dev/null)
export PORTRAIT_ID=$(cat /tmp/portrait_id.txt 2>/dev/null)

# ============================================================
# Verify Landscape Image Scaling
# ============================================================
# Fetch attachment metadata which stores the native width/height after edit
LANDSCAPE_META=$(wp post meta get "$LANDSCAPE_ID" _wp_attachment_metadata --format=json --allow-root 2>/dev/null || echo "{}")
export LANDSCAPE_WIDTH=$(echo "$LANDSCAPE_META" | jq -r '.width // "0"' 2>/dev/null || echo "0")

# ============================================================
# Verify Portrait Image Rotation and Alt Text
# ============================================================
# When WP edits an image, it saves the new file path with an '-e[timestamp]' suffix
export PORTRAIT_FILE=$(wp post meta get "$PORTRAIT_ID" _wp_attached_file --allow-root 2>/dev/null || echo "")
export PORTRAIT_ALT=$(wp post meta get "$PORTRAIT_ID" _wp_attachment_image_alt --allow-root 2>/dev/null || echo "")

# ============================================================
# Verify Post Creation
# ============================================================
export POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Meet the Team') AND post_type='post' ORDER BY ID DESC LIMIT 1" 2>/dev/null)

export POST_PUBLISHED="false"
export POST_CONTENT=""

if [ -n "$POST_ID" ]; then
    STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID" 2>/dev/null)
    if [ "$STATUS" = "publish" ]; then
        POST_PUBLISHED="true"
    fi
    # Get raw post content
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID" 2>/dev/null)
    export POST_CONTENT
fi

# ============================================================
# Secure JSON Generation via Python
# ============================================================
python3 << 'EOF'
import json
import os

data = {
    "landscape_id": os.environ.get('LANDSCAPE_ID', ''),
    "landscape_width": int(os.environ.get('LANDSCAPE_WIDTH', '0')),
    "portrait_id": os.environ.get('PORTRAIT_ID', ''),
    "portrait_file": os.environ.get('PORTRAIT_FILE', ''),
    "portrait_alt": os.environ.get('PORTRAIT_ALT', ''),
    "post_found": bool(os.environ.get('POST_ID')),
    "post_published": os.environ.get('POST_PUBLISHED') == 'true',
    "post_content": os.environ.get('POST_CONTENT', '')
}

with open('/tmp/edit_media_result.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/edit_media_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/edit_media_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="