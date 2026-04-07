#!/bin/bash
set -euo pipefail

echo "=== Setting up assign_channel_moderator task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# 3. Ensure clean state: Remove 'moderator' role from agent.user if it exists
echo "Ensuring clean state (removing moderator role if present)..."

# Login as admin for API access
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get Channel ID for release-updates
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
  
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)
  
  # Get Agent User ID (from seed manifest or API)
  AGENT_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=agent.user" 2>/dev/null || true)
  AGENT_ID=$(echo "$AGENT_INFO" | jq -r '.user._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ] && [ -n "$AGENT_ID" ]; then
    # Save IDs for export script to use later
    echo "$CHANNEL_ID" > /tmp/target_channel_id.txt
    echo "$AGENT_ID" > /tmp/target_agent_id.txt

    # Check current roles
    ROLES_RESP=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.roles?roomId=${CHANNEL_ID}" 2>/dev/null || true)
    
    # If agent is moderator, remove it
    IS_MOD=$(echo "$ROLES_RESP" | jq -r --arg uid "$AGENT_ID" \
      '.roles[]? | select(.u._id == $uid and .roles[] == "moderator") | .u._id' 2>/dev/null || true)
    
    if [ -n "$IS_MOD" ]; then
      echo "Agent user is currently moderator. Removing role..."
      curl -sS -X POST \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        -H "Content-Type: application/json" \
        -d "{\"roomId\":\"$CHANNEL_ID\",\"userId\":\"$AGENT_ID\"}" \
        "${ROCKETCHAT_BASE_URL}/api/v1/channels.removeModerator" >/dev/null || true
    else
      echo "Agent user is not a moderator. Clean state confirmed."
    fi
  else
    echo "WARNING: Could not resolve Channel ID or Agent ID via API."
  fi
else
  echo "WARNING: Failed to authenticate as admin during setup."
fi

# 4. Start Firefox at Login Page
echo "Starting Firefox..."
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="