#!/bin/bash
set -euo pipefail

echo "=== Setting up create_custom_slash_command task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (creation timestamp check)
date +%s > /tmp/task_start_timestamp.txt

# 2. Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# 3. Ensure clean state: Delete the slash command if it already exists
echo "Ensuring clean state (removing existing 'deploy-status' command if any)..."

# Login as admin to get token
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # List integrations and find ID of 'deploy-status'
  INTEGRATION_ID=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" 2>/dev/null | \
    jq -r '.integrations[] | select(.command == "deploy-status") | ._id')
  
  if [ -n "$INTEGRATION_ID" ] && [ "$INTEGRATION_ID" != "null" ]; then
    echo "Found existing integration $INTEGRATION_ID, deleting..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"webhook-outgoing\", \"integrationId\": \"$INTEGRATION_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/integrations.remove" >/dev/null 2>&1 || true
  fi
else
  echo "WARNING: Could not log in to clean up existing integrations. Task may fail if it already exists."
fi

# 4. Start Firefox at the login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# 5. Capture initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="