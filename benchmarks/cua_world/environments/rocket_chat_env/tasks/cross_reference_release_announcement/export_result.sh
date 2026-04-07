#!/bin/bash
set -euo pipefail

echo "=== Exporting cross_reference_release_announcement task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Extract the dynamically generated target ID from the seed manifest
TARGET_MSG_ID=""
TARGET_TAG=""
if [ -f "$SEED_MANIFEST_FILE" ]; then
  TARGET_TAG=$(jq -r '.target_release.tag_name // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || true)
  if [ -n "$TARGET_TAG" ]; then
    TARGET_MSG_ID=$(jq -r --arg tag "$TARGET_TAG" '.seeded_releases[] | select(.tag_name == $tag) | .message_id' "$SEED_MANIFEST_FILE" 2>/dev/null || true)
  fi
fi

# Retrieve agent's messages from the #general channel
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

GENERAL_MESSAGES="[]"
if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    HISTORY=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=20" 2>/dev/null || true)
    GENERAL_MESSAGES=$(echo "$HISTORY" | jq -c '.messages // []' 2>/dev/null || echo "[]")
  fi
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_tag": "$TARGET_TAG",
    "target_msg_id": "$TARGET_MSG_ID",
    "general_messages": $GENERAL_MESSAGES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON and ensure permissions so verifier can read it
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="