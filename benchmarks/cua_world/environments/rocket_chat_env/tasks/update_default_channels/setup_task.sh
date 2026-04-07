#!/bin/bash
set -euo pipefail

echo "=== Setting up update_default_channels task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Authenticate as admin for setup
echo "Authenticating as admin..."
for _ in $(seq 1 30); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

# Get Auth Token headers for setup requests
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to get admin token for setup"
  exit 1
fi

# 1. Clean state: Ensure 'announcements' channel does NOT exist
echo "Ensuring 'announcements' channel does not exist..."
CHANNEL_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=announcements" 2>/dev/null)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty')

if [ -n "$CHANNEL_ID" ]; then
  echo "Deleting existing 'announcements' channel..."
  curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"roomId\": \"$CHANNEL_ID\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.delete" >/dev/null
fi

# 2. Clean state: Reset Default_Channels to include 'general' and NOT 'announcements'
echo "Resetting Default_Channels setting..."
# Ideally we want just "general", but let's see what's currently there and just ensure clean state
# For simplicity in setup, we force it to "general" to ensure the agent has to do work
curl -sS -X POST -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"value": "general"}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Default_Channels" >/dev/null

# Prepare Browser
echo "Preparing Firefox..."
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state captured at /tmp/task_initial.png"

echo "=== Task setup complete ==="