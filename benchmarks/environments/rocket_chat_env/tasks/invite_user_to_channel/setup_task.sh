#!/bin/bash
set -euo pipefail

echo "=== Setting up invite_user_to_channel task ==="

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

# Clean state: delete "deployment-log" channel if it already exists
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Check if public channel exists
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=deployment-log" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    echo "Removing pre-existing deployment-log channel for clean state"
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$CHANNEL_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.delete" 2>/dev/null || true
    sleep 1
  fi

  # Also check if it exists as a private group
  GROUP_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/groups.info?roomName=deployment-log" 2>/dev/null || true)
  GROUP_ID=$(echo "$GROUP_INFO" | jq -r '.group._id // empty' 2>/dev/null || true)

  if [ -n "$GROUP_ID" ]; then
    echo "Removing pre-existing deployment-log private group for clean state"
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$GROUP_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/groups.delete" 2>/dev/null || true
    sleep 1
  fi
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
