#!/bin/bash
echo "=== Exporting publish_podcast_episode result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Retrieve Category ID for 'Podcasts'
CATEGORY_ID=$(wp_db_query "SELECT t.term_id FROM wp_terms t INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='category' AND LOWER(TRIM(t.name)) = 'podcasts' LIMIT 1")

# Retrieve Attachment ID for the properly titled audio
ATTACHMENT_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='attachment' AND post_mime_type LIKE 'audio/%' AND LOWER(TRIM(post_title))='tech insights episode 1 audio' LIMIT 1")

# Retrieve Post ID for the properly titled published post
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='post' AND post_status='publish' AND LOWER(TRIM(post_title))='tech insights ep 1: the future of cloud computing' LIMIT 1")

POST_CONTENT=""
POST_CATEGORIES=""

if [ -n "$POST_ID" ]; then
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID")
    POST_CATEGORIES=$(get_post_categories "$POST_ID")
fi

# Package all data cleanly using jq
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --arg cat_id "$CATEGORY_ID" \
  --arg att_id "$ATTACHMENT_ID" \
  --arg post_id "$POST_ID" \
  --arg content "$POST_CONTENT" \
  --arg categories "$POST_CATEGORIES" \
  '{
    category_id: $cat_id,
    attachment_id: $att_id,
    post_id: $post_id,
    post_content: $content,
    post_categories: $categories,
    timestamp: "'$(date -Iseconds)'"
  }' > "$TEMP_JSON"

# Move securely
rm -f /tmp/publish_podcast_episode_result.json 2>/dev/null || sudo rm -f /tmp/publish_podcast_episode_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/publish_podcast_episode_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/publish_podcast_episode_result.json
chmod 666 /tmp/publish_podcast_episode_result.json 2>/dev/null || sudo chmod 666 /tmp/publish_podcast_episode_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result file preview:"
cat /tmp/publish_podcast_episode_result.json