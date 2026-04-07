#!/bin/bash
# Export script for publish_data_journalism_post task (post_task hook)

echo "=== Exporting publish_data_journalism_post result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Expected post title
EXPECTED_TITLE="2023 Significant Earthquakes Report"

# Query the database for the post ID by exact title
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$EXPECTED_TITLE')) AND post_type='post' ORDER BY ID DESC LIMIT 1")

# If we found the post, extract details and export safely via Python
if [ -n "$POST_ID" ]; then
    echo "Found post with ID: $POST_ID"
    
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID")
    POST_CATEGORIES=$(get_post_categories "$POST_ID")
    POST_TAGS=$(get_post_tags "$POST_ID")
    
    # Save raw content to file to avoid bash escaping issues with huge HTML strings
    docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -N -e "SELECT post_content FROM wp_posts WHERE ID=$POST_ID" > /tmp/raw_post_content.txt

    # Generate JSON via Python to guarantee correct escaping
    python3 << PYEOF
import json
import os

result = {
    "post_found": True,
    "post_id": "$POST_ID",
    "post_status": "$POST_STATUS",
    "categories": "$POST_CATEGORIES",
    "tags": "$POST_TAGS"
}

try:
    with open('/tmp/raw_post_content.txt', 'r', encoding='utf-8') as f:
        result['post_content'] = f.read()
except Exception as e:
    result['post_content'] = ""
    result['error'] = str(e)

with open('/tmp/publish_data_journalism_post_result.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
PYEOF

else:
    echo "Post '$EXPECTED_TITLE' NOT found."
    python3 << PYEOF
import json
with open('/tmp/publish_data_journalism_post_result.json', 'w', encoding='utf-8') as f:
    json.dump({"post_found": False}, f)
PYEOF
fi

# Set permissions for verifier.py
chmod 666 /tmp/publish_data_journalism_post_result.json 2>/dev/null || sudo chmod 666 /tmp/publish_data_journalism_post_result.json 2>/dev/null || true

echo ""
echo "Export Complete. Result saved."