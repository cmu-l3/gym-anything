#!/bin/bash
set -euo pipefail

echo "=== Exporting rebrand_workspace_announce task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_SITE_NAME=$(cat /tmp/initial_site_name.txt 2>/dev/null || echo "Rocket.Chat")

# Authenticate to API to fetch results
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

FINAL_SITE_NAME=""
GENERAL_MESSAGES="[]"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Fetch current Site_Name
  SITE_NAME_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Site_Name" 2>/dev/null || true)
  FINAL_SITE_NAME=$(echo "$SITE_NAME_RESP" | jq -r '.value // empty')

  # 2. Fetch #general channel history
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
    
    # Extract just the message text and timestamp to keep JSON small
    GENERAL_MESSAGES=$(echo "$HISTORY" | jq -c '[.messages[]? | {msg: .msg, ts: .ts}]' 2>/dev/null || echo "[]")
  fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_site_name": "$INITIAL_SITE_NAME",
    "final_site_name": "$FINAL_SITE_NAME",
    "general_messages": $GENERAL_MESSAGES
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="