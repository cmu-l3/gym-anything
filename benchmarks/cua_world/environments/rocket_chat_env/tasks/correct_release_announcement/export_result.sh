#!/bin/bash
set -euo pipefail

echo "=== Exporting correct_release_announcement result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence of completed state
take_screenshot /tmp/task_final.png

# Read setup variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
MSG_ID=$(cat /tmp/target_message_id.txt 2>/dev/null || echo "")

# Re-authenticate to query API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

MSG_FOUND="false"
MSG_TEXT=""
EDITED_AT=""
EDITED_BY=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ] && [ -n "$MSG_ID" ]; then
  # Query the specific message by its original ID
  # This proves the agent edited the message rather than deleting it and creating a new one
  MSG_RESP=$(curl -sS -G \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    --data-urlencode "msgId=${MSG_ID}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/chat.getMessage" 2>/dev/null || true)

  MSG_FOUND=$(echo "$MSG_RESP" | jq -r '.success // false')

  if [ "$MSG_FOUND" == "true" ]; then
    MSG_TEXT=$(echo "$MSG_RESP" | jq -r '.message.msg // empty')
    EDITED_AT=$(echo "$MSG_RESP" | jq -r '.message.editedAt // empty')
    EDITED_BY=$(echo "$MSG_RESP" | jq -r '.message.editedBy.username // empty')
  fi
fi

# Check if browser was actually running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Safely construct JSON using jq to handle potentially weird text characters
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --argjson start "$TASK_START" \
  --arg msg_id "$MSG_ID" \
  --argjson found "$MSG_FOUND" \
  --arg text "$MSG_TEXT" \
  --arg edited_at "$EDITED_AT" \
  --arg edited_by "$EDITED_BY" \
  --argjson app_running "$APP_RUNNING" \
  '{
    "task_start": $start,
    "target_msg_id": $msg_id,
    "message_found": $found,
    "message_text": $text,
    "edited_at": $edited_at,
    "edited_by": $edited_by,
    "app_was_running": $app_running
  }' > "$TEMP_JSON"

# Move file to final location handling permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="