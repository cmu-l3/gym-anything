#!/bin/bash
set -euo pipefail

echo "=== Setting up archive_project_channel task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 1. Wait for Rocket.Chat API
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# 2. Login as Admin to perform setup
echo "Logging in as admin for setup..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to authenticate for setup"
  exit 1
fi

# 3. Create or Reset #project-alpha channel
CHANNEL_NAME="project-alpha"
echo "Ensuring channel #$CHANNEL_NAME exists..."

# Check if exists
INFO_RESP=$(curl -sS -X GET \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=${CHANNEL_NAME}" 2>/dev/null)

CHANNEL_ID=$(echo "$INFO_RESP" | jq -r '.channel._id // empty')

if [ -z "$CHANNEL_ID" ] || [ "$CHANNEL_ID" == "null" ]; then
  # Create channel
  CREATE_RESP=$(curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${CHANNEL_NAME}\", \"members\": []}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.create" 2>/dev/null)
  CHANNEL_ID=$(echo "$CREATE_RESP" | jq -r '.channel._id // empty')
  echo "Created channel ID: $CHANNEL_ID"
else
  echo "Channel exists ($CHANNEL_ID). Checking state..."
  # If archived, unarchive it to ensure clean start state
  IS_ARCHIVED=$(echo "$INFO_RESP" | jq -r '.channel.archived // false')
  if [ "$IS_ARCHIVED" == "true" ]; then
    echo "Channel was archived. Unarchiving..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"roomId\": \"$CHANNEL_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.unarchive" >/dev/null
  fi
fi

# 4. Seed messages to make it realistic
echo "Seeding project history..."
MESSAGES=(
  "Project Alpha kickoff meeting scheduled for Monday."
  "Here are the initial wireframes for review."
  "Backend API is 50% complete."
  "Client approved the design phase."
  "Code freeze initiated."
  "Final deployment successful. Great job everyone!"
  "Project retrospective completed. We are ready to wrap up."
)

for msg in "${MESSAGES[@]}"; do
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"channel\": \"#${CHANNEL_NAME}\", \"text\": \"$msg\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/chat.postMessage" >/dev/null
  sleep 0.2
done

# 5. Prepare Browser
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
# Navigate explicitly to login to ensure clean start
navigate_to_url "$ROCKETCHAT_LOGIN_URL"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="