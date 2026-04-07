#!/bin/bash
set -euo pipefail

echo "=== Setting up create_project_team task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
rm -f /tmp/task_start.png 2>/dev/null || true
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/task_start_timestamp

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

# Authenticate for setup API calls
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Cleaning up any pre-existing state..."
  
  # 1. Delete "Q2 Marketing" team if it exists
  TEAM_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/teams.info?teamName=Q2%20Marketing" 2>/dev/null || true)
  TEAM_ID=$(echo "$TEAM_INFO" | jq -r '.team._id // empty')
  
  if [ -n "$TEAM_ID" ]; then
    echo "Deleting pre-existing team..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"teamId\":\"$TEAM_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/teams.delete" 2>/dev/null || true
    sleep 1
  fi

  # 2. Delete "social-media" room if it exists
  ROOM_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/rooms.info?roomName=social-media" 2>/dev/null || true)
  ROOM_ID=$(echo "$ROOM_INFO" | jq -r '.room._id // empty')
  ROOM_TYPE=$(echo "$ROOM_INFO" | jq -r '.room.t // empty')
  
  if [ -n "$ROOM_ID" ]; then
    echo "Deleting pre-existing social-media room..."
    if [ "$ROOM_TYPE" = "p" ]; then
      curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d "{\"roomId\":\"$ROOM_ID\"}" "${ROCKETCHAT_BASE_URL}/api/v1/groups.delete" 2>/dev/null || true
    else
      curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d "{\"roomId\":\"$ROOM_ID\"}" "${ROCKETCHAT_BASE_URL}/api/v1/channels.delete" 2>/dev/null || true
    fi
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