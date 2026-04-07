#!/bin/bash
set -euo pipefail

echo "=== Exporting react_to_release_messages task result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Login to REST API to verify state programmatically
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
    echo "ERROR: Could not log in to API to verify results"
    exit 1
fi

# Fetch Channel ID for #release-updates
CHANNEL_INFO=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

# Pull channel history
if [ -n "$CHANNEL_ID" ]; then
    HISTORY=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=50" 2>/dev/null || true)
    
    TOTAL_MSGS=$(echo "$HISTORY" | jq '.messages | length' 2>/dev/null || echo "0")
else
    HISTORY="{}"
    TOTAL_MSGS="0"
fi

# Identify the target oldest/newest message IDs from the seed manifest
if [ -f "$SEED_MANIFEST_FILE" ]; then
    OLDEST_MSG_ID=$(jq -r '.seeded_releases[0].message_id // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || echo "")
    NEWEST_MSG_ID=$(jq -r '.seeded_releases[-1].message_id // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || echo "")
else
    OLDEST_MSG_ID=""
    NEWEST_MSG_ID=""
fi

# Extract reaction objects mapped exclusively to those two messages
if [ -n "$OLDEST_MSG_ID" ] && [ "$TOTAL_MSGS" -gt 0 ]; then
    OLDEST_REACTIONS=$(echo "$HISTORY" | jq -c ".messages[] | select(._id == \"$OLDEST_MSG_ID\") | .reactions // {}" 2>/dev/null || echo "{}")
else
    OLDEST_REACTIONS="{}"
fi

if [ -n "$NEWEST_MSG_ID" ] && [ "$TOTAL_MSGS" -gt 0 ]; then
    NEWEST_REACTIONS=$(echo "$HISTORY" | jq -c ".messages[] | select(._id == \"$NEWEST_MSG_ID\") | .reactions // {}" 2>/dev/null || echo "{}")
else
    NEWEST_REACTIONS="{}"
fi

# Prevent empty bash variables resolving to invalid JSON structure
[ -z "$OLDEST_REACTIONS" ] && OLDEST_REACTIONS="{}"
[ -z "$NEWEST_REACTIONS" ] && NEWEST_REACTIONS="{}"

# Output consolidated payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "total_messages": $TOTAL_MSGS,
    "oldest_message_id": "$OLDEST_MSG_ID",
    "newest_message_id": "$NEWEST_MSG_ID",
    "oldest_reactions": $OLDEST_REACTIONS,
    "newest_reactions": $NEWEST_REACTIONS,
    "channel_id": "$CHANNEL_ID"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="