#!/bin/bash
set -euo pipefail

echo "=== Setting up disable_public_registration task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
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

# Authenticate via REST API to reset the setting state to 'Public'
LOGIN_PAYLOAD=$(jq -nc --arg user "$ROCKETCHAT_TASK_USERNAME" --arg pass "$ROCKETCHAT_TASK_PASSWORD" '{user: $user, password: $pass}')
LOGIN_RESP=$(curl -sS -X POST -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Resetting Accounts_RegistrationForm to 'Public' to ensure clean state..."
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"value": "Public"}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_RegistrationForm" >/dev/null 2>&1 || true
    
  echo "Public" > /tmp/initial_registration_state.txt
else
  echo "ERROR: Could not get auth token to reset state"
  exit 1
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

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="