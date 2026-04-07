#!/bin/bash
set -euo pipefail

echo "=== Exporting fix_ci_webhook task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Task end screenshot saved to /tmp/task_end.png"

# Auth using the task user
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

WEBHOOK_CHANNEL=""
WEBHOOK_USERNAME=""
TEST_MESSAGE_COUNT=0

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Fetch current integration details via API
  INTEGRATIONS_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" || echo "{}")
  INTEGRATION_JSON=$(echo "$INTEGRATIONS_RESP" | jq -c '.integrations[]? | select(.name == "CI Notification Bot")' | head -1 || echo "")
  
  if [ -n "$INTEGRATION_JSON" ]; then
    WEBHOOK_CHANNEL=$(echo "$INTEGRATION_JSON" | jq -r '.channel // empty')
    WEBHOOK_USERNAME=$(echo "$INTEGRATION_JSON" | jq -r '.username // empty')
  fi

  # 2. Search for the functional test message in #build-alerts
  ROOM_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=build-alerts" || echo "{}")
  ROOM_ID=$(echo "$ROOM_INFO" | jq -r '.channel._id // empty')

  if [ -n "$ROOM_ID" ]; then
    HISTORY=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${ROOM_ID}&count=50" || echo "{}")
    
    # We look for messages posted by "build-bot" indicating the functional webhook firing
    TEST_MESSAGE_COUNT=$(echo "$HISTORY" | jq '[.messages[]? | select((.u.username == "build-bot") or (.alias == "build-bot"))] | length' 2>/dev/null || echo "0")
  fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "webhook_channel": "$WEBHOOK_CHANNEL",
  "webhook_username": "$WEBHOOK_USERNAME",
  "test_message_count": $TEST_MESSAGE_COUNT,
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="