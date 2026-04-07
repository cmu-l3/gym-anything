#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_maintenance_announcement task ==="

source /workspace/scripts/task_utils.sh

# Record initial timestamps and clean up previous state
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

# Get API token to clean the initial state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Reset Announcement Settings to a clean (disabled/default) state
if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Resetting announcement settings to default..."
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":false}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Display_Announcement" >/dev/null 2>&1 || true
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":""}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Announcement" >/dev/null 2>&1 || true
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":"primary"}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Announcement_Style" >/dev/null 2>&1 || true
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":true}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Announcement_Allow_Dismissal" >/dev/null 2>&1 || true
fi

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

# Make sure window is in focus
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="