#!/bin/bash
echo "=== Exporting create_reusable_patterns task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_BLOCK_COUNT=$(cat /tmp/initial_block_count.txt 2>/dev/null || echo "0")

# 1. Fetch all reusable blocks (wp_block) created during or before the task
# We use MySQL TO_BASE64 to safely handle raw block content containing heavy HTML/JSON quotes
BLOCKS_JSON_ARRAY="["
FIRST_BLOCK=true

# Fetching blocks (id, title, base64_content, creation_timestamp)
BLOCKS_DATA=$(wp_db_query "SELECT ID, post_title, TO_BASE64(post_content), UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE post_type='wp_block'" 2>/dev/null)

if [ -n "$BLOCKS_DATA" ]; then
    while IFS=$'\t' read -r id title b64_content created_ts; do
        if [ "$FIRST_BLOCK" = true ]; then
            FIRST_BLOCK=false
        else
            BLOCKS_JSON_ARRAY="${BLOCKS_JSON_ARRAY},"
        fi
        
        # Safe escaping for JSON string limits
        CLEAN_TITLE=$(echo "$title" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
        
        BLOCKS_JSON_ARRAY="${BLOCKS_JSON_ARRAY} {
            \"id\": \"$id\",
            \"title\": \"$CLEAN_TITLE\",
            \"content_b64\": \"$b64_content\",
            \"created_ts\": ${created_ts:-0}
        }"
    done <<< "$BLOCKS_DATA"
fi
BLOCKS_JSON_ARRAY="${BLOCKS_JSON_ARRAY} ]"

# 2. Fetch the target news article post
ARTICLE_FOUND="false"
ARTICLE_ID=""
ARTICLE_B64_CONTENT=""
ARTICLE_CREATED_TS=0

# Looking for post title containing "City Council" (published)
ARTICLE_DATA=$(wp_db_query "SELECT ID, TO_BASE64(post_content), UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE post_type='post' AND post_status='publish' AND LOWER(post_title) LIKE '%city council%' ORDER BY ID DESC LIMIT 1" 2>/dev/null)

if [ -n "$ARTICLE_DATA" ]; then
    ARTICLE_FOUND="true"
    ARTICLE_ID=$(echo "$ARTICLE_DATA" | cut -f1)
    ARTICLE_B64_CONTENT=$(echo "$ARTICLE_DATA" | cut -f2)
    ARTICLE_CREATED_TS=$(echo "$ARTICLE_DATA" | cut -f3)
fi

# Build final JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "initial_block_count": $INITIAL_BLOCK_COUNT,
    "blocks": $BLOCKS_JSON_ARRAY,
    "article": {
        "found": $ARTICLE_FOUND,
        "id": "$ARTICLE_ID",
        "content_b64": "$ARTICLE_B64_CONTENT",
        "created_ts": ${ARTICLE_CREATED_TS:-0}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="