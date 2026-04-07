#!/bin/bash
set -euo pipefail

echo "=== Setting up enforce_message_immutability task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
rm -f /tmp/task_start.png 2>/dev/null || true

# Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Authenticate to record initial state
for _ in $(seq 1 30); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Failed to authenticate as admin for setup"
  exit 1
fi

# Reset settings to known "bad" defaults (Deleting=True, Editing=True, Block=0, History=False)
# This ensures the agent actually has to do work
echo "Resetting message settings to defaults..."

# Helper to set a setting
set_setting() {
  local id="$1"
  local val="$2"
  curl -sS -X POST \
    -H "X-Auth-Token: $RC_TOKEN" \
    -H "X-User-Id: $RC_USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"value\": $val}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/$id" >/dev/null
}

# Get token from the api_login function's side effect or re-auth manually
# api_login sets internal variables but not exported ones easily, let's re-auth specifically for curl usage
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login")

RC_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
RC_USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

set_setting "Message_AllowDeleting" "true"
set_setting "Message_AllowEditing" "true"
set_setting "Message_AllowEditing_BlockEditInMinutes" "0"
set_setting "Message_KeepHistory" "false"

# Record initial values
echo "Recording initial state..."
curl -sS -H "X-Auth-Token: $RC_TOKEN" -H "X-User-Id: $RC_USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowDeleting" > /tmp/init_deleting.json
curl -sS -H "X-Auth-Token: $RC_TOKEN" -H "X-User-Id: $RC_USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowEditing_BlockEditInMinutes" > /tmp/init_block.json
curl -sS -H "X-Auth-Token: $RC_TOKEN" -H "X-User-Id: $RC_USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_KeepHistory" > /tmp/init_history.json

# Launch Firefox at login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="