#!/bin/bash
set -euo pipefail

echo "=== Setting up create_release_discussion task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Verify Rocket.Chat is up
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 300; then
  echo "ERROR: Rocket.Chat API not reachable"
  exit 1
fi

# 3. Authenticate to prepare state
echo "Authenticating as admin..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo '{}')

RC_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
RC_USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$RC_TOKEN" ] || [ -z "$RC_USERID" ]; then
  echo "ERROR: Failed to authenticate to setup task state"
  exit 1
fi

# 4. Clean up: Delete any existing discussion with the target name
# Discussions are rooms, so we search and delete
echo "Checking for pre-existing discussions..."
EXISTING_ROOMS=$(curl -sS -X GET \
  -H "X-Auth-Token: $RC_TOKEN" \
  -H "X-User-Id: $RC_USERID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/rooms.adminRooms?filter=Upgrade%20Planning&count=50" 2>/dev/null)

echo "$EXISTING_ROOMS" | jq -r '.rooms[]? | ._id' | while read -r room_id; do
  if [ -n "$room_id" ]; then
    echo "Deleting pre-existing discussion room: $room_id"
    curl -sS -X POST \
      -H "X-Auth-Token: $RC_TOKEN" \
      -H "X-User-Id: $RC_USERID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$room_id\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/rooms.delete" >/dev/null 2>&1 || true
  fi
done

# 5. Record the parent channel ID for verification later
CHANNEL_INFO=$(curl -sS -X GET \
  -H "X-Auth-Token: $RC_TOKEN" \
  -H "X-User-Id: $RC_USERID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty')
echo "$CHANNEL_ID" > /tmp/parent_channel_id.txt
echo "Parent channel ID recorded: $CHANNEL_ID"

# 6. Launch Firefox at the login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="