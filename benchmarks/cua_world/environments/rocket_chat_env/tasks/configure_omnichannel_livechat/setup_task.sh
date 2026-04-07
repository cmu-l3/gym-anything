#!/bin/bash
set -euo pipefail

echo "=== Setting up Omnichannel LiveChat configuration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is healthy
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# --- Ensure Omnichannel is DISABLED (clean initial state) ---
echo "Ensuring Omnichannel is disabled for clean starting state..."

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Disable Omnichannel (ensure clean starting state)
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"value": false}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Livechat_enabled" >/dev/null 2>&1 || true

  # Remove agent.user as livechat agent if previously added
  # First get ID of agent.user
  AGENT_USER_INFO=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=agent.user" 2>/dev/null || true)
  AGENT_USER_ID=$(echo "$AGENT_USER_INFO" | jq -r '.user._id // empty' 2>/dev/null || true)

  if [ -n "$AGENT_USER_ID" ]; then
    # Delete from livechat agents
    curl -sS -X DELETE \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/livechat/users/agent/$AGENT_USER_ID" >/dev/null 2>&1 || true
  fi

  # Remove any existing "Technical Support" department
  # First get list of departments
  DEPT_LIST=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/livechat/department" 2>/dev/null || true)
  
  # Find ID of "Technical Support"
  DEPT_ID=$(echo "$DEPT_LIST" | jq -r '.departments[]? | select(.name == "Technical Support") | ._id // empty' 2>/dev/null || true)

  if [ -n "$DEPT_ID" ]; then
    echo "Removing pre-existing department: $DEPT_ID"
    curl -sS -X DELETE \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/livechat/department/$DEPT_ID" >/dev/null 2>&1 || true
  fi

  echo "Initial state cleaned: Omnichannel disabled, no agent, no department"
else
  echo "WARNING: Could not authenticate to clean initial state"
fi

# Start Firefox on the Rocket.Chat home page (logged in as admin)
restart_firefox "$ROCKETCHAT_BASE_URL" 4

sleep 5

# Focus Firefox and maximize
focus_firefox || true

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Omnichannel LiveChat task setup complete ==="