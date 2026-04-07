#!/bin/bash
set -euo pipefail

echo "=== Setting up lock_down_user_profiles task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Wait for Rocket.Chat API
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Try login repeatedly until Rocket.Chat is fully ready
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

# Perform setup via API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Setting initial state: ensuring all profile edit settings are ENABLED"
  
  SETTINGS=(
    "Accounts_AllowRealNameChange"
    "Accounts_AllowUsernameChange"
    "Accounts_AllowEmailChange"
    "Accounts_AllowUserAvatarChange"
    "Accounts_AllowDeleteOwnAccount"
  )

  for setting in "${SETTINGS[@]}"; do
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d '{"value": true}' \
      "${ROCKETCHAT_BASE_URL}/api/v1/settings/${setting}" >/dev/null 2>&1 || true
  done
else
  echo "ERROR: Could not log in to set initial state"
  exit 1
fi

if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="