#!/bin/bash
set -euo pipefail

echo "=== Exporting add_custom_emoji task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

EMOJI_FOUND="false"
EMOJI_HAS_EXTENSION="false"
MSG_FOUND="false"
MSG_EPOCH="0"
MSG_TEXT=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Check for custom emoji
  EMOJI_LIST=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/emoji-custom.list" 2>/dev/null || echo "{}")
    
  EMOJI_DATA=$(echo "$EMOJI_LIST" | jq -c '.emojis.update[]? | select(.name == "rocket_release")' 2>/dev/null || echo "")

  if [ -n "$EMOJI_DATA" ]; then
    EMOJI_FOUND="true"
    EXTENSION=$(echo "$EMOJI_DATA" | jq -r '.extension // empty' 2>/dev/null || true)
    if [ -n "$EXTENSION" ] && [ "$EXTENSION" != "null" ]; then
      EMOJI_HAS_EXTENSION="true"
    fi
  fi

  # 2. Check for message in channel
  CHANNEL_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || echo "{}")
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    HISTORY=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=20" 2>/dev/null || echo "{}")
      
    TARGET_MSG=$(echo "$HISTORY" | jq -c '.messages[]? | select(.msg | contains(":rocket_release:")) | limit(1; .)' 2>/dev/null || echo "")
    
    if [ -n "$TARGET_MSG" ]; then
      MSG_FOUND="true"
      # Convert ISO8601 timestamp to unix epoch using jq
      MSG_EPOCH=$(echo "$TARGET_MSG" | jq -r '(.ts | fromdateiso8601) // 0' 2>/dev/null || echo "0")
      MSG_TEXT=$(echo "$TARGET_MSG" | jq -r '.msg // empty' | sed 's/"/\\"/g' 2>/dev/null || true)
    fi
  fi
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_timestamp": $TASK_START,
  "task_end_timestamp": $TASK_END,
  "emoji_found": $EMOJI_FOUND,
  "emoji_has_extension": $EMOJI_HAS_EXTENSION,
  "message_found": $MSG_FOUND,
  "message_epoch": $MSG_EPOCH,
  "message_text": "$MSG_TEXT"
}
EOF

chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="