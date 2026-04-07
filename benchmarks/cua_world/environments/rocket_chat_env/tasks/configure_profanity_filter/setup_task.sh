#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_profanity_filter task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Wait for Rocket.Chat to be available
wait_for_http "${ROCKETCHAT_BASE_URL}/api/v1/info" 120

# Log in as admin via API to reset state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Could not authenticate as admin"
  exit 1
fi

HEADERS=(-H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json")

# Ensure the bad words filter is DISABLED (clean starting state)
echo "Resetting bad words filter to disabled state..."
curl -sS -X POST "${HEADERS[@]}" \
  -d '{"value": false}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowBadWordsFilter" > /dev/null 2>&1 || true

# Clear any existing custom bad words list
echo "Clearing custom bad words list..."
curl -sS -X POST "${HEADERS[@]}" \
  -d '{"value": ""}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_BadWordsFilterList" > /dev/null 2>&1 || true

# Record initial state for anti-gaming verification
echo "Recording initial settings state..."
INITIAL_FILTER=$(curl -sS -X GET "${HEADERS[@]}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowBadWordsFilter" 2>/dev/null | jq -r '.value // "unknown"')
INITIAL_LIST=$(curl -sS -X GET "${HEADERS[@]}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_BadWordsFilterList" 2>/dev/null | jq -r '.value // "unknown"')

cat > /tmp/task_initial_state.json << EOF
{
  "filter_enabled": ${INITIAL_FILTER},
  "filter_list": "${INITIAL_LIST}",
  "timestamp": $(date +%s)
}
EOF

# Count current messages in #general for comparison
GENERAL_MSG_COUNT=$(curl -sS -X GET "${HEADERS[@]}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomName=general&count=1" 2>/dev/null \
  | jq '.messages | length // 0' 2>/dev/null || echo "0")
  
# If API fails (e.g. empty channel), just set to 0
if [ -z "$GENERAL_MSG_COUNT" ]; then GENERAL_MSG_COUNT=0; fi
echo "$GENERAL_MSG_COUNT" > /tmp/initial_general_msg_count.txt

echo "Initial state: filter_enabled=${INITIAL_FILTER}, filter_list='${INITIAL_LIST}', general_msgs=${GENERAL_MSG_COUNT}"

# Start Firefox with Rocket.Chat login page
restart_firefox "${ROCKETCHAT_BASE_URL}/login" 3
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="