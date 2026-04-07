#!/bin/bash
echo "=== Exporting recover_content result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Read IDs from ground truth
if [ -f /var/lib/app/ground_truth/task_ids.json ]; then
    POST_2023_ID=$(python3 -c "import json; print(json.load(open('/var/lib/app/ground_truth/task_ids.json'))['post_2023_id'])")
    POST_2024_ORIG_ID=$(python3 -c "import json; print(json.load(open('/var/lib/app/ground_truth/task_ids.json'))['post_2024_orig_id'])")
    POST_DRAFT_ID=$(python3 -c "import json; print(json.load(open('/var/lib/app/ground_truth/task_ids.json'))['post_draft_id'])")
else
    echo "ERROR: ground truth IDs not found"
    exit 1
fi

# Get state of 2024 original post
ORIG_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_2024_ORIG_ID")
ORIG_NAME=$(wp_db_query "SELECT post_name FROM wp_posts WHERE ID=$POST_2024_ORIG_ID")

# Get state of draft (it might be deleted, so handle carefully)
DRAFT_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_DRAFT_ID" || echo "")
if [ -z "$DRAFT_STATUS" ]; then
    DRAFT_STATUS="deleted"
fi
DRAFT_NAME=$(wp_db_query "SELECT post_name FROM wp_posts WHERE ID=$POST_DRAFT_ID" || echo "")

# Categories & Tags
ORIG_CATS=$(get_post_categories "$POST_2024_ORIG_ID" 2>/dev/null || echo "")
ORIG_TAGS=$(get_post_tags "$POST_2024_ORIG_ID" 2>/dev/null || echo "")
POST_2023_TAGS=$(get_post_tags "$POST_2023_ID" 2>/dev/null || echo "")

# 2023 Content
POST_2023_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_2023_ID" 2>/dev/null)
ESCAPED_CONTENT=$(echo "$POST_2023_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 5000)

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "orig_status": "${ORIG_STATUS:-}",
    "orig_name": "${ORIG_NAME:-}",
    "draft_status": "${DRAFT_STATUS:-}",
    "draft_name": "${DRAFT_NAME:-}",
    "orig_categories": "$(echo "$ORIG_CATS" | sed 's/"/\\"/g')",
    "orig_tags": "$(echo "$ORIG_TAGS" | sed 's/"/\\"/g')",
    "post_2023_tags": "$(echo "$POST_2023_TAGS" | sed 's/"/\\"/g')",
    "post_2023_content": "$ESCAPED_CONTENT"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="