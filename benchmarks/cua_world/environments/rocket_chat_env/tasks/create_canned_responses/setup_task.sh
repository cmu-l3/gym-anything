#!/bin/bash
set -euo pipefail

echo "=== Setting up Create Canned Responses task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Rocket.Chat availability
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
  echo "ERROR: Rocket.Chat API not reachable"
  exit 1
fi

# Authenticate as Admin
echo "Authenticating as admin to configure environment..."
for _ in {1..10}; do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 3
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Could not login as admin"
  exit 1
fi

# Get Auth headers
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$TOKEN" ] || [ -z "$USERID" ]; then
  echo "ERROR: Failed to extract auth token"
  exit 1
fi

echo "Configuring Omnichannel state..."

# 1. Enable Omnichannel
curl -sS -X POST \
  -H "X-Auth-Token: $TOKEN" \
  -H "X-User-Id: $USERID" \
  -H "Content-Type: application/json" \
  -d '{"value": true}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Livechat_enabled" >/dev/null

# 2. Ensure Admin is a Livechat Agent (required to see/manage canned responses)
IS_AGENT=$(curl -sS -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/livechat/users/agent/${USERID}" 2>/dev/null | jq -r '.success')

if [ "$IS_AGENT" != "true" ]; then
  echo "Registering admin as Livechat agent..."
  curl -sS -X POST \
    -H "X-Auth-Token: $TOKEN" \
    -H "X-User-Id: $USERID" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${ROCKETCHAT_TASK_USERNAME}\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/livechat/users/agent" >/dev/null
fi

# 3. Clear ANY existing canned responses (Clean Slate)
echo "Clearing existing canned responses..."
CANNED_RESP=$(curl -sS -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/canned-responses" 2>/dev/null)

echo "$CANNED_RESP" | jq -r '.cannedResponses[]?._id' | while read -r resp_id; do
  if [ -n "$resp_id" ]; then
    curl -sS -X DELETE \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "{\"_id\": \"$resp_id\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/canned-responses" >/dev/null
  fi
done

# Prepare Firefox
if ! restart_firefox "${ROCKETCHAT_LOGIN_URL}" 5; then
  echo "ERROR: Failed to start Firefox"
  exit 1
fi

# Ensure window focus and maximization
focus_firefox
maximize_active_window

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="