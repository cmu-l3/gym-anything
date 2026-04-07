#!/bin/bash
set -euo pipefail

echo "=== Exporting thread_reply_release task result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png

# Load task metadata
TASK_START=$(jq -r '.task_start' /tmp/thread_task_meta.json 2>/dev/null || echo "0")
TARGET_MSG_ID=$(jq -r '.target_msg_id' /tmp/thread_task_meta.json 2>/dev/null || echo "")

# Initialize output JSON objects
THREAD_MESSAGES_JSON="[]"
CHANNEL_MESSAGES_JSON="[]"

# Authenticate with Rocket.Chat API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Get channel history to detect if agent posted as regular message instead of thread
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || echo "{}")
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty')

  if [ -n "$CHANNEL_ID" ]; then
    HISTORY_RESP=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=20" 2>/dev/null || echo "{}")
    CHANNEL_MESSAGES_JSON=$(echo "$HISTORY_RESP" | jq -c '.messages // []')
  fi

  # 2. Get thread messages for the target parent message
  if [ -n "$TARGET_MSG_ID" ]; then
    THREAD_RESP=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/chat.getThreadMessages?tmid=${TARGET_MSG_ID}" 2>/dev/null || echo "{}")
    THREAD_MESSAGES_JSON=$(echo "$THREAD_RESP" | jq -c '.messages // []')
  fi
fi

# Create export JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "target_msg_id": "$TARGET_MSG_ID",
  "thread_messages": $THREAD_MESSAGES_JSON,
  "channel_messages": $CHANNEL_MESSAGES_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="