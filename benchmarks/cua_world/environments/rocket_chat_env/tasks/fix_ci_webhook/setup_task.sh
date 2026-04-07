#!/bin/bash
set -euo pipefail

echo "=== Setting up fix_ci_webhook task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# Get auth token
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Authenticated via API successfully."
  
  # Ensure target channels exist
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" -d '{"name":"legacy-builds"}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.create" >/dev/null 2>&1 || true

  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" -d '{"name":"build-alerts"}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.create" >/dev/null 2>&1 || true

  # Remove any existing integrations with this name to ensure a clean starting state
  INTEGRATIONS_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list")
  echo "$INTEGRATIONS_RESP" | jq -r '.integrations[]? | select(.name == "CI Notification Bot") | ._id' 2>/dev/null | while read -r int_id; do
    if [ -n "$int_id" ]; then
      echo "Deleting pre-existing integration: $int_id"
      curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
        -H "Content-Type: application/json" -d "{\"type\":\"webhook-incoming\",\"integrationId\":\"$int_id\"}" \
        "${ROCKETCHAT_BASE_URL}/api/v1/integrations.remove" >/dev/null 2>&1 || true
    fi
  done

  # Create the misconfigured integration (points to legacy-builds, as rocket.cat)
  CREATE_RESP=$(curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"type": "webhook-incoming", "name": "CI Notification Bot", "enabled": true, "username": "rocket.cat", "channel": "#legacy-builds", "scriptEnabled": false}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.create")
  
  INT_SUCCESS=$(echo "$CREATE_RESP" | jq -r '.success // empty')
  if [ "$INT_SUCCESS" != "true" ]; then
    echo "WARNING: Failed to create integration via REST API: $CREATE_RESP"
  else
    echo "Misconfigured integration successfully generated."
  fi
else
  echo "ERROR: Failed to authenticate to API for setup."
fi

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="