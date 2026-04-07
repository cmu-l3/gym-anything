#!/bin/bash
set -euo pipefail

echo "=== Setting up correct_release_announcement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
rm -f /tmp/task_start.png 2>/dev/null || true
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Wait for Rocket.Chat API to be reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Authenticate to set up the task
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

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to obtain auth token for setup"
  exit 1
fi

# Inject the incorrect release announcement that needs to be edited
CHANNEL_NAME="release-updates"
BAD_MSG_TEXT="Rocket.Chat Release 8.0.0 is now available. This is a major update with significant performance improvements."

echo "Injecting incorrect release announcement..."
POST_RESP=$(curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"#${CHANNEL_NAME}\",\"text\":\"${BAD_MSG_TEXT}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/chat.postMessage" 2>/dev/null || true)

MSG_ID=$(echo "$POST_RESP" | jq -r '.message._id // empty')

if [ -z "$MSG_ID" ] || [ "$MSG_ID" == "null" ]; then
  echo "ERROR: Failed to post target message. Response: $POST_RESP"
  exit 1
fi

# Save the target message ID so we can verify the agent EDITED it rather than recreating it
echo "$MSG_ID" > /tmp/target_message_id.txt
echo "Target Message ID: $MSG_ID"

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

# Ensure deterministic start state at the login screen
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Capture initial screenshot as evidence of starting state
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="