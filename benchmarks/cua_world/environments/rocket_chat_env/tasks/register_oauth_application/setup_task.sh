#!/bin/bash
set -euo pipefail

echo "=== Setting up register_oauth_application task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
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

# Authenticate via REST API to clean state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Clean state: Remove any existing app with this name
  APPS=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/oauth-apps.list" 2>/dev/null || true)
  
  echo "$APPS" | jq -r '.oauthApps[]? | select(.name == "Release Dashboard") | ._id' 2>/dev/null | while read -r app_id; do
    if [ -n "$app_id" ]; then
      echo "Deleting pre-existing OAuth app: $app_id"
      curl -sS -X POST \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        -H "Content-Type: application/json" \
        -d "{\"appId\":\"$app_id\"}" \
        "${ROCKETCHAT_BASE_URL}/api/v1/oauth-apps.delete" 2>/dev/null || true
      sleep 1
    fi
  done
  
  # Record initial count of OAuth Apps
  NEW_APPS=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/oauth-apps.list" 2>/dev/null || true)
  INITIAL_COUNT=$(echo "$NEW_APPS" | jq '.oauthApps | length' 2>/dev/null || echo "0")
  echo "$INITIAL_COUNT" > /tmp/initial_oauth_count.txt
fi

# Copy seed manifest for reference
if [ ! -f "$SEED_MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$SEED_MANIFEST_FILE"
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