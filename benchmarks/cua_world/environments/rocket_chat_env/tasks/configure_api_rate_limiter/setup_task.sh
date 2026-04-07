#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure API Rate Limiter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Reset Rate Limiter configuration to a known "bad" state
# 1. Login to get token
echo "Authenticating as admin to reset settings..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Resetting API Rate Limiter settings..."
  
  # Disable Rate Limiter
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"value": false}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_Enable_Rate_Limiter" >/dev/null 2>&1 || true

  # Set Default Count to 100 (default is often 10, 60 or 100, setting to 100 ensures 20 is a change)
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"value": 100}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_Default_Count" >/dev/null 2>&1 || true

  echo "Settings reset complete."
else
  echo "WARNING: Failed to authenticate for setup. Task starting state may be inconsistent."
fi

# Start Firefox at Login Page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Wait for window and focus
if wait_for_window "Rocket.Chat" 30; then
  focus_firefox || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="