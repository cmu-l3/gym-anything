#!/bin/bash
set -euo pipefail

echo "=== Setting up add_custom_emoji task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (Unix epoch) for anti-gaming checks
rm -f /tmp/task_start.png 2>/dev/null || true
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Ensure the required image file exists and is owned by the agent
echo "Generating custom emoji image asset..."
convert -size 128x128 xc:transparent \
    -fill '#3498db' -draw "circle 64,64 64,10" \
    -fill '#e74c3c' -draw "polygon 64,20 40,90 88,90" \
    -fill '#f1c40f' -draw "polygon 54,90 74,90 64,110" \
    /home/ga/emoji_rocket_release.png 2>/dev/null || true
chmod 644 /home/ga/emoji_rocket_release.png
chown ga:ga /home/ga/emoji_rocket_release.png

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Authenticate via API to clean up state
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. DELETE pre-existing emoji to ensure clean state
  EMOJI_LIST=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/emoji-custom.list" 2>/dev/null || true)
  
  EMOJI_ID=$(echo "$EMOJI_LIST" | jq -r '.emojis.update[] | select(.name == "rocket_release") | ._id' 2>/dev/null || true)
  if [ -n "$EMOJI_ID" ]; then
    echo "Cleaning up pre-existing custom emoji for clean state..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"emojiId\":\"$EMOJI_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/emoji-custom.delete" 2>/dev/null || true
  fi

  # 2. DELETE pre-existing messages containing the emoji from the channel
  CHANNEL_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    HISTORY=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHANNEL_ID}&count=50" 2>/dev/null || true)
      
    echo "$HISTORY" | jq -r '.messages[]? | select(.msg | contains(":rocket_release:")) | ._id' 2>/dev/null | while read -r msg_id; do
      if [ -n "$msg_id" ]; then
        echo "Deleting pre-existing emoji message: $msg_id"
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