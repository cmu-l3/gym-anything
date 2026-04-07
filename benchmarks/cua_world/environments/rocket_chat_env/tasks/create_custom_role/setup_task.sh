#!/bin/bash
set -euo pipefail

echo "=== Setting up create_custom_role task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Authenticate via API to prepare the clean state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Could not authenticate to Rocket.Chat API for setup."
  exit 1
fi

# Ensure the "release-manager" role does NOT already exist (Clean State)
# We fetch all roles, check for our target name, and delete if found
ROLE_INFO=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/roles.list" 2>/dev/null || true)

TARGET_ROLE_ID=$(echo "$ROLE_INFO" | jq -r '.roles[]? | select(.name == "release-manager") | ._id' 2>/dev/null || true)

if [ -n "$TARGET_ROLE_ID" ]; then
  echo "Removing pre-existing release-manager role to ensure clean state (ID: $TARGET_ROLE_ID)"
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"roleId\":\"$TARGET_ROLE_ID\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/roles.delete" 2>/dev/null || true
  sleep 1
fi

# Verify the target user exists and ONLY has the "user" role
USER_INFO=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=agent.user" 2>/dev/null || true)

TARGET_USER_ID=$(echo "$USER_INFO" | jq -r '.user._id // empty' 2>/dev/null || true)

if [ -n "$TARGET_USER_ID" ]; then
  echo "Resetting roles for agent.user..."
  # To reset, we just set their roles to ["user"]
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"data\": {\"userId\":\"$TARGET_USER_ID\", \"roles\": [\"user\"]}}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.update" 2>/dev/null || true
fi

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

# Ensure window is focused and ready
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Take starting evidence
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="