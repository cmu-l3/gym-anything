#!/bin/bash
set -euo pipefail

echo "=== Setting up customize_sidebar_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
rm -f /tmp/task_start.png 2>/dev/null || true

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

# Use API to force a "messy" sidebar state before the agent starts
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Resetting Account Preferences to default messy state..."
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"data": {"sidebarGroupByType": false, "sidebarSortby": "activity", "sidebarViewMode": "medium"}}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.setPreferences" >/dev/null 2>&1 || true

  echo "Fetching room IDs..."
  ROOM_REL=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null | jq -r '.channel._id // empty')
  ROOM_GEN=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general" 2>/dev/null | jq -r '.channel._id // empty')

  if [ -n "$ROOM_REL" ]; then
    echo "Ensuring #release-updates is not favorited..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$ROOM_REL\",\"favorite\":false}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/rooms.favorite" >/dev/null 2>&1 || true
  fi

  if [ -n "$ROOM_GEN" ]; then
    echo "Ensuring #general is open and visible..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$ROOM_GEN\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/rooms.open" >/dev/null 2>&1 || true
  fi
fi

# Copy seed manifest for reference
if [ ! -f "$SEED_MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$SEED_MANIFEST_FILE"
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