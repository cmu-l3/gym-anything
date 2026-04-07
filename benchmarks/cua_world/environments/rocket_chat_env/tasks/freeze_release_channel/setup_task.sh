#!/bin/bash
set -euo pipefail

echo "=== Setting up task: freeze_release_channel ==="

# Source shared utilities
TASK_UTILS="/workspace/scripts/task_utils.sh"
if [ -f "$TASK_UTILS" ]; then
  source "$TASK_UTILS"
else
  echo "ERROR: Missing task utilities: $TASK_UTILS"
  exit 1
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="Admin1234!"
CHANNEL_NAME="release-updates"
AGENT_USERNAME="agent.user"

# Wait for Rocket.Chat to be available
wait_for_http "$ROCKETCHAT_BASE_URL" 120

echo "Configuring initial channel state..."

# Authenticate to prepare state
LOGIN_RESPONSE=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USERNAME}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get Channel ID
  CHANNEL_INFO=$(curl -sS -X GET \
    -H "X-Auth-Token: ${AUTH_TOKEN}" \
    -H "X-User-Id: ${USER_ID}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=${CHANNEL_NAME}" 2>/dev/null || echo "{}")

  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)
  
  # Record initial state for verifier
  echo "$CHANNEL_INFO" > /tmp/initial_channel_state.json

  if [ -n "$CHANNEL_ID" ]; then
    # 1. Ensure channel is writable (NOT read-only)
    curl -sS -X POST \
      -H "X-Auth-Token: ${AUTH_TOKEN}" \
      -H "X-User-Id: ${USER_ID}" \
      -H "Content-Type: application/json" \
      -d '{"roomId":"'"${CHANNEL_ID}"'","readOnly":false}' \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.setReadOnly" >/dev/null 2>&1 || true

    # 2. Ensure announcement is empty
    curl -sS -X POST \
      -H "X-Auth-Token: ${AUTH_TOKEN}" \
      -H "X-User-Id: ${USER_ID}" \
      -H "Content-Type: application/json" \
      -d '{"roomId":"'"${CHANNEL_ID}"'","announcement":""}' \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.setAnnouncement" >/dev/null 2>&1 || true

    # 3. Ensure agent.user is NOT a moderator
    # First get agent user ID
    ROLES_INFO=$(curl -sS -X GET \
      -H "X-Auth-Token: ${AUTH_TOKEN}" \
      -H "X-User-Id: ${USER_ID}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.roles?roomId=${CHANNEL_ID}" 2>/dev/null || echo "{}")
    
    AGENT_ID=$(echo "$ROLES_INFO" | jq -r ".roles[]? | select(.u.username == \"${AGENT_USERNAME}\") | .u._id" 2>/dev/null || true)
    
    if [ -n "$AGENT_ID" ]; then
      curl -sS -X POST \
        -H "X-Auth-Token: ${AUTH_TOKEN}" \
        -H "X-User-Id: ${USER_ID}" \
        -H "Content-Type: application/json" \
        -d '{"roomId":"'"${CHANNEL_ID}"'","userId":"'"${AGENT_ID}"'"}' \
        "${ROCKETCHAT_BASE_URL}/api/v1/channels.removeModerator" >/dev/null 2>&1 || true
    fi
  fi
  echo "Channel state reset complete."
else
  echo "WARNING: Could not authenticate to clean channel state. Task may fail verification."
fi

# Start Firefox at login page
restart_firefox "${ROCKETCHAT_BASE_URL}" 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="