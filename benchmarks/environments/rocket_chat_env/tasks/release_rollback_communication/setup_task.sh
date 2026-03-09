#!/bin/bash
set -euo pipefail

echo "=== Setting up release_rollback_communication task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="release_rollback_communication"

rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get auth token"
  exit 1
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  fi
}

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
  echo "Ensured user: $username"
}

create_user_if_not_exists "qa.lead" "QA Lead" "qa.lead@company.local"
create_user_if_not_exists "devops.engineer" "DevOps Engineer" "devops.engineer@company.local"
create_user_if_not_exists "product.manager" "Product Manager" "product.manager@company.local"

# The seed script already created #release-updates with release messages.
# Find the message IDs for 7.8.5 and 8.0.2 releases from the seed manifest.
MANIFEST=$(cat "$SEED_MANIFEST_FILE" 2>/dev/null || echo '{}')
MSG_785=""
MSG_802=""

# Extract message IDs from seeded releases
MSG_785=$(echo "$MANIFEST" | jq -r '.seeded_releases[] | select(.tag_name == "7.8.5") | .message_id // empty' 2>/dev/null || true)
MSG_802=$(echo "$MANIFEST" | jq -r '.seeded_releases[] | select(.tag_name == "8.0.2") | .message_id // empty' 2>/dev/null || true)

# If not found in manifest, search channel history
if [ -z "$MSG_785" ] || [ -z "$MSG_802" ]; then
  RELEASE_CH_INFO=$(rc_api GET "channels.info?roomName=release-updates")
  RELEASE_CH_ID=$(echo "$RELEASE_CH_INFO" | jq -r '.channel._id // empty')

  if [ -n "$RELEASE_CH_ID" ]; then
    HIST=$(rc_api GET "channels.history?roomId=${RELEASE_CH_ID}&count=50")

    if [ -z "$MSG_785" ]; then
      MSG_785=$(echo "$HIST" | jq -r '[.messages[] | select(.msg | test("7\\.8\\.5"; "i"))][0]._id // empty' 2>/dev/null || true)
    fi
    if [ -z "$MSG_802" ]; then
      MSG_802=$(echo "$HIST" | jq -r '[.messages[] | select(.msg | test("8\\.0\\.2"; "i"))][0]._id // empty' 2>/dev/null || true)
    fi
  fi
fi

# Clean up any pre-existing rollback channel
rc_api POST "channels.delete" '{"roomName":"rollback-8-0-2-coordination"}' >/dev/null 2>&1 || true

# Clear any existing announcement on release-updates
RELEASE_CH_INFO=$(rc_api GET "channels.info?roomName=release-updates")
RELEASE_CH_ID=$(echo "$RELEASE_CH_INFO" | jq -r '.channel._id // empty')
if [ -n "$RELEASE_CH_ID" ]; then
  rc_api POST "channels.setAnnouncement" \
    "{\"roomId\":\"${RELEASE_CH_ID}\",\"announcement\":\"\"}" >/dev/null 2>&1 || true
fi

# Clear admin user status
rc_api POST "users.setStatus" '{"message":"","status":"online"}' >/dev/null 2>&1 || true

# Record baseline
cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "msg_785_id": "${MSG_785:-}",
  "msg_802_id": "${MSG_802:-}",
  "release_channel_id": "${RELEASE_CH_ID:-}"
}
EOF

date +%s > "/tmp/${TASK_NAME}_start_ts"

if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo "=== Task setup complete ==="
echo "Release 7.8.5 msg ID: ${MSG_785:-unknown}"
echo "Release 8.0.2 msg ID: ${MSG_802:-unknown}"
