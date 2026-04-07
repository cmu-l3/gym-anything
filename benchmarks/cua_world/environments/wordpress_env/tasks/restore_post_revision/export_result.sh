#!/bin/bash
# Export script for restore_post_revision task

echo "=== Exporting restore_post_revision result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read baseline info
BASELINE_FILE="/tmp/post_baseline.json"
EXPECTED_POST_ID=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE')).get('post_id', 0))" 2>/dev/null || echo "0")
INITIAL_REV_COUNT=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE')).get('initial_revision_count', 0))" 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

echo "Baseline Post ID: $EXPECTED_POST_ID"
echo "Initial Revision Count: $INITIAL_REV_COUNT"

cd /var/www/html/wordpress

# Find the post (Check if it's the expected ID, or if they deleted/recreated it)
ACTUAL_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Annual Marketing Strategy Report') AND post_type='post' AND post_status IN ('publish', 'draft', 'pending', 'private') ORDER BY ID DESC LIMIT 1")

if [ -z "$ACTUAL_POST_ID" ]; then
    # Maybe they renamed it, fallback to checking the expected ID directly
    ACTUAL_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE ID=$EXPECTED_POST_ID AND post_type='post' LIMIT 1")
fi

POST_FOUND="false"
POST_TITLE=""
POST_STATUS=""
POST_CONTENT=""
POST_MODIFIED_TS=0
CURRENT_REV_COUNT=0
POST_ID_MATCHES="false"

if [ -n "$ACTUAL_POST_ID" ]; then
    POST_FOUND="true"
    echo "Found post with ID: $ACTUAL_POST_ID"
    
    if [ "$ACTUAL_POST_ID" = "$EXPECTED_POST_ID" ]; then
        POST_ID_MATCHES="true"
    fi
    
    POST_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$ACTUAL_POST_ID")
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$ACTUAL_POST_ID")
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$ACTUAL_POST_ID")
    POST_MODIFIED=$(wp_db_query "SELECT post_modified FROM wp_posts WHERE ID=$ACTUAL_POST_ID")
    
    # Convert modified time to timestamp
    POST_MODIFIED_TS=$(date -d "$POST_MODIFIED" +%s 2>/dev/null || echo "0")
    
    # Get current revision count
    CURRENT_REV_COUNT=$(wp post list --post_type=revision --post_parent="$ACTUAL_POST_ID" --format=count --allow-root 2>/dev/null || echo "0")
else
    echo "Post not found!"
fi

# We use Python to construct the JSON safely, escaping all content correctly
python3 << PYEOF
import json
import os

result = {
    "task_start_time": $TASK_START,
    "expected_post_id": $EXPECTED_POST_ID,
    "actual_post_id": "$ACTUAL_POST_ID",
    "post_id_matches": "$POST_ID_MATCHES" == "true",
    "post_found": "$POST_FOUND" == "true",
    "post_title": """$POST_TITLE""",
    "post_status": "$POST_STATUS",
    "post_content": """$POST_CONTENT""",
    "post_modified_ts": $POST_MODIFIED_TS,
    "initial_revision_count": $INITIAL_REV_COUNT,
    "current_revision_count": $CURRENT_REV_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/restore_post_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/restore_post_result.json
echo "Result exported to /tmp/restore_post_result.json"

echo "=== Export complete ==="