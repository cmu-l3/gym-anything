#!/bin/bash
set -euo pipefail

echo "=== Setting up enable_katex_math_rendering task ==="

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

# Ensure KaTeX is explicitly disabled initially to prevent gaming
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Disabling KaTeX settings for clean task state..."
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":false}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Enabled" >/dev/null || true
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":false}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Dollar_Syntax" >/dev/null || true
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json" -d '{"value":false}' "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Parenthesis_Syntax" >/dev/null || true
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

# Capture initial state screenshot
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="