#!/bin/bash
set -euo pipefail

echo "=== Setting up offboard_legacy_users task ==="

source /workspace/scripts/task_utils.sh

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

# Get token for API calls
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Function to ensure user exists and is active
  ensure_user_active() {
      local username=$1
      local name=$2
      local email=$3
      
      USER_INFO=$(curl -sS \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=$username" 2>/dev/null || true)
        
      TARGET_USER_ID=$(echo "$USER_INFO" | jq -r '.user._id // empty')
      
      if [ -z "$TARGET_USER_ID" ] || [ "$TARGET_USER_ID" = "null" ]; then
          echo "Creating user $username"
          curl -sS -X POST \
            -H "X-Auth-Token: $AUTH_TOKEN" \
            -H "X-User-Id: $USER_ID" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"name\":\"$name\",\"password\":\"Password123!\",\"username\":\"$username\",\"active\":true,\"roles\":[\"user\"],\"verified\":true,\"joinDefaultChannels\":true}" \
            "${ROCKETCHAT_BASE_URL}/api/v1/users.create" 2>/dev/null >/dev/null || true
      else
          echo "Setting user $username to active"
          curl -sS -X POST \
            -H "X-Auth-Token: $AUTH_TOKEN" \
            -H "X-User-Id: $USER_ID" \
            -H "Content-Type: application/json" \
            -d "{\"activeStatus\":true,\"userId\":\"$TARGET_USER_ID\"}" \
            "${ROCKETCHAT_BASE_URL}/api/v1/users.setActiveStatus" 2>/dev/null >/dev/null || true
      fi
  }

  ensure_user_active "contractor.jane" "Jane Smith" "jane.smith@contractor.local"
  ensure_user_active "consultant.mike" "Mike Jones" "mike.jones@consultant.local"
else
  echo "WARNING: Could not obtain auth token for setup"
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

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="