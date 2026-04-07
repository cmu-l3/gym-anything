#!/bin/bash
set -euo pipefail

echo "=== Setting up create_outgoing_webhook task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming measures
date +%s > /tmp/task_start_time.txt

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

# Clean state: remove existing target outgoing webhook if any
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

INITIAL_COUNT="0"
if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch integrations
  INTEGRATIONS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" 2>/dev/null || echo '{}')
  
  # Find and delete matching ones to ensure clean state
  echo "$INTEGRATIONS_RESP" | jq -r '.integrations[]? | select(.type == "webhook-outgoing" and (.name | ascii_downcase) == "release security monitor") | ._id' 2>/dev/null | while read -r int_id; do
    if [ -n "$int_id" ]; then
      echo "Deleting pre-existing integration: $int_id"
      curl -sS -X POST \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        -H "Content-Type: application/json" \
        -d "{\"integrationId\":\"$int_id\", \"type\": \"webhook-outgoing\"}" \
        "${ROCKETCHAT_BASE_URL}/api/v1/integrations.remove" 2>/dev/null || true
    fi
  done

  # Count existing outgoing webhooks after cleanup
  INTEGRATIONS_RESP2=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" 2>/dev/null || echo '{}')
  INITIAL_COUNT=$(echo "$INTEGRATIONS_RESP2" | jq '[.integrations[]? | select(.type == "webhook-outgoing")] | length' 2>/dev/null || echo "0")
fi

echo "$INITIAL_COUNT" > /tmp/initial_outgoing_count.txt
echo "Initial outgoing webhook count: $INITIAL_COUNT"

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