#!/bin/bash
set -euo pipefail

echo "=== Setting up thread_reply_release task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
rm -f /tmp/task_start.png 2>/dev/null || true
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Locate seed manifest
MANIFEST_FILE="/tmp/rocket_chat_seed_manifest.json"
if [ ! -f "$MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$MANIFEST_FILE"
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

# Establish clean state: identify the target message and delete any pre-existing thread replies
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

TARGET_MSG_ID=""
TARGET_TAG=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ] && [ -f "$MANIFEST_FILE" ]; then
  # Get the target release tag from manifest
  TARGET_TAG=$(jq -r '.target_release.tag_name // empty' "$MANIFEST_FILE")
  
  # Find the most recent seeded message ID
  TARGET_MSG_ID=$(jq -r '.seeded_releases[-1].message_id // empty' "$MANIFEST_FILE")

  if [ -n "$TARGET_MSG_ID" ]; then
    echo "Target Message ID: $TARGET_MSG_ID (Tag: $TARGET_TAG)"
    
    # Delete any existing thread replies on this message to ensure clean state
    THREAD_MSGS=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/chat.getThreadMessages?tmid=${TARGET_MSG_ID}" 2>/dev/null || true)
      
    echo "$THREAD_MSGS" | jq -r '.messages[]? | select(._id != "'"$TARGET_MSG_ID"'") | ._id' 2>/dev/null | while read -r msg_id; do
      if [ -n "$msg_id" ]; then
        echo "Deleting pre-existing thread reply: $msg_id"
        curl -sS -X POST \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          -H "Content-Type: application/json" \
          -d "{\"roomId\":\"GENERAL\",\"msgId\":\"$msg_id\"}" \
          "${ROCKETCHAT_BASE_URL}/api/v1/chat.delete" 2>/dev/null || true
      fi
    done
  fi
fi

# Save target metadata for the export/verifier scripts
cat > /tmp/thread_task_meta.json << EOF
{
  "task_start": $TASK_START,
  "target_msg_id": "$TARGET_MSG_ID",
  "target_tag": "$TARGET_TAG"
}
EOF
chmod 644 /tmp/thread_task_meta.json

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