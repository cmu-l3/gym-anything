#!/bin/bash
set -euo pipefail

echo "=== Setting up create_restricted_invite task ==="

source /workspace/scripts/task_utils.sh

# Record start time and clear previous state files
rm -f /tmp/task_start.png /tmp/task_result.json /tmp/mongo_invites.json 2>/dev/null || true
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

# Clean state 1: Delete any existing invites from the database
echo "Clearing existing workspace invites..."
docker exec rc-mongodb mongosh --quiet --eval '
  try {
      var targetDb = db.getSiblingDB("rocketchat");
      var cols = targetDb.getCollectionNames();
      cols.forEach(function(colName) {
         if (colName.toLowerCase().indexOf("invite") !== -1) {
            targetDb.getCollection(colName).deleteMany({});
         }
      });
  } catch (e) {}
' >/dev/null 2>&1 || true

# Clean state 2: Delete existing messages matching our target text
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get channel info
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    # Find messages containing the target text
    HISTORY=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=50" 2>/dev/null || true)

    # Unpin and delete
    echo "$HISTORY" | jq -r '.messages[]? | select(.msg | contains("Official Beta Program Invite Link")) | ._id' 2>/dev/null | while read -r msg_id; do
      if [ -n "$msg_id" ]; then
        echo "Deleting pre-existing target message: $msg_id"
        curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d "{\"messageId\":\"$msg_id\"}" "${ROCKETCHAT_BASE_URL}/api/v1/chat.unPinMessage" 2>/dev/null || true
        curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d "{\"roomId\":\"$CHANNEL_ID\",\"msgId\":\"$msg_id\"}" "${ROCKETCHAT_BASE_URL}/api/v1/chat.delete" 2>/dev/null || true
      fi
    done
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