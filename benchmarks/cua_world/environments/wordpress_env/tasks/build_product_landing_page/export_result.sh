#!/bin/bash
# Export script for build_product_landing_page task
# Gathers verification data and exports to JSON

echo "=== Exporting build_product_landing_page result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Retrieve initial counts
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
INITIAL_MEDIA_COUNT=$(cat /tmp/initial_media_count 2>/dev/null || echo "0")

CURRENT_PAGE_COUNT=$(wp_cli post list --post_type=page --format=count 2>/dev/null || echo "0")
CURRENT_MEDIA_COUNT=$(wp_cli post list --post_type=attachment --format=count 2>/dev/null || echo "0")

echo "Page count: $INITIAL_PAGE_COUNT -> $CURRENT_PAGE_COUNT"
echo "Media count: $INITIAL_MEDIA_COUNT -> $CURRENT_MEDIA_COUNT"

# ============================================================
# Check Media Upload
# ============================================================
IMAGE_UPLOADED="false"
IMAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='attachment' AND (post_title LIKE '%hero-bg%' OR guid LIKE '%hero-bg%') ORDER BY ID DESC LIMIT 1" 2>/dev/null)

if [ -n "$IMAGE_ID" ]; then
    IMAGE_UPLOADED="true"
    echo "Found uploaded image 'hero-bg.jpg' with ID: $IMAGE_ID"
fi

# ============================================================
# Find Landing Page
# ============================================================
PAGE_FOUND="false"
PAGE_ID=""
PAGE_STATUS=""
PAGE_CONTENT=""

# Try exact title first
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Urban Photography Book Launch' AND post_type='page' ORDER BY ID DESC LIMIT 1" 2>/dev/null)

if [ -z "$PAGE_ID" ]; then
    # Try case-insensitive or partial
    PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(post_title) LIKE '%urban photography book launch%' AND post_type='page' ORDER BY ID DESC LIMIT 1" 2>/dev/null)
fi

if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    echo "Found landing page with ID: $PAGE_ID"
    
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID" 2>/dev/null)
    
    # Use WP-CLI to get content (safer for multiline HTML/blocks than raw mysql query)
    cd /var/www/html/wordpress
    PAGE_CONTENT=$(wp post get $PAGE_ID --field=post_content --allow-root 2>/dev/null)
    
    echo "Page Status: $PAGE_STATUS"
    echo "Content Length: ${#PAGE_CONTENT}"
else
    echo "Landing page NOT found"
fi

# ============================================================
# Create JSON result using Python to safely escape content
# ============================================================
python3 << PYEOF
import json
import os

result = {
    "initial_page_count": int("$INITIAL_PAGE_COUNT" or 0),
    "current_page_count": int("$CURRENT_PAGE_COUNT" or 0),
    "initial_media_count": int("$INITIAL_MEDIA_COUNT" or 0),
    "current_media_count": int("$CURRENT_MEDIA_COUNT" or 0),
    "image_uploaded": "$IMAGE_UPLOADED" == "true",
    "page_found": "$PAGE_FOUND" == "true",
    "page_status": "$PAGE_STATUS",
    "page_content": """$PAGE_CONTENT"""
}

# Write securely to tmp file
with open('/tmp/landing_page_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/landing_page_result.json

echo ""
echo "Result saved to /tmp/landing_page_result.json"
echo "=== Export complete ==="