#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_custom_notification_sound task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / debugging
take_screenshot /tmp/task_end.png

# Fetch authentication token for API queries
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to authenticate to export API data."
  # Still export an empty JSON to prevent verifier crashes
  echo "{}" > /tmp/task_result.json
  exit 0
fi

echo "Authenticating to API..."

# Query 1: Custom Sounds List
CUSTOM_SOUNDS=$(curl -sS -G \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/custom-sounds.list" 2>/dev/null || echo "{}")

# Query 2: Get #release-updates Channel ID
CHANNEL_INFO=$(curl -sS -G \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  --data-urlencode "roomName=release-updates" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.info" 2>/dev/null || echo "{}")

CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

# Query 3: Get User Subscriptions for the channel (to verify notification settings)
SUB_INFO="{}"
if [ -n "$CHANNEL_ID" ]; then
  SUB_INFO=$(curl -sS -G \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    --data-urlencode "roomId=${CHANNEL_ID}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/subscriptions.getOne" 2>/dev/null || echo "{}")
fi

# Package state into a JSON export file safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --argjson sounds "$CUSTOM_SOUNDS" \
  --argjson sub "$SUB_INFO" \
  '{
    "custom_sounds_response": $sounds,
    "subscription_response": $sub,
    "timestamp": "'$(date -Iseconds)'"
  }' > "$TEMP_JSON"

# Move file safely into place to be read by copy_from_env
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/task_result.json"
echo "=== Export complete ==="