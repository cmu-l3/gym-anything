#!/bin/bash
set -euo pipefail

echo "=== Setting up rebrand_workspace_announce task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

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

# Authenticate via API to configure clean initial state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Enforce a clean starting state for Site_Name
  echo "Resetting Site_Name to 'Rocket.Chat'..."
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"value\":\"Rocket.Chat\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Site_Name" >/dev/null 2>&1 || true

  # 2. Record the initial Site_Name just to be sure
  SITE_NAME_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Site_Name" 2>/dev/null || true)
  INITIAL_SITE_NAME=$(echo "$SITE_NAME_RESP" | jq -r '.value // "Rocket.Chat"' 2>/dev/null)
  echo "$INITIAL_SITE_NAME" > /tmp/initial_site_name.txt

  # 3. Purge any pre-existing messages in #general that contain the target string
  # to prevent accidental passes from previous runs
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    HISTORY=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=50" 2>/dev/null || true)
      
    echo "$HISTORY" | jq -r '.messages[]? | select(.msg | contains("NovaTech Engineering Hub")) | ._id' 2>/dev/null | while read -r msg_id; do
      if [ -n "$msg_id" ]; then
        echo "Deleting pre-existing target message: $msg_id"
        curl -sS -X POST \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          -H "Content-Type: application/json" \
          -d "{\"roomId\":\"$CHANNEL_ID\",\"msgId\":\"$msg_id\"}" \
          "${ROCKETCHAT_BASE_URL}/api/v1/chat.delete" 2>/dev/null || true
      fi
    done
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