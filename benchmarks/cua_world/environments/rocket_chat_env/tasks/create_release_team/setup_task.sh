#!/bin/bash
set -euo pipefail

echo "=== Setting up create_release_team task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
rm -f /tmp/task_initial_state.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure Rocket.Chat is responsive
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
    echo "ERROR: Rocket.Chat API is not reachable"
    exit 1
fi

# Authenticate as admin to prepare state
echo "Authenticating to clean up state..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
AUTH_USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$AUTH_USERID" ]; then
  echo "Checking for pre-existing team 'release-management'..."
  
  # Check if team exists
  TEAM_INFO=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $AUTH_USERID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/teams.info?teamName=release-management" 2>/dev/null || true)

  TEAM_ID=$(echo "$TEAM_INFO" | jq -r '.teamInfo._id // empty' 2>/dev/null || true)
  
  if [ -n "$TEAM_ID" ]; then
    echo "Deleting pre-existing team (ID: $TEAM_ID) to ensure clean state..."
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $AUTH_USERID" \
      -H "Content-Type: application/json" \
      -d "{\"teamId\":\"$TEAM_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/teams.delete" >/dev/null 2>&1 || true
    sleep 2
  else
    echo "Team does not exist. State is clean."
  fi
  
  # Ensure the release-updates channel exists (it should from seeding, but verify)
  CHANNEL_INFO=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $AUTH_USERID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)
  
  if [ -z "$CHANNEL_ID" ]; then
    echo "WARNING: release-updates channel missing. Re-running seed logic might be needed."
    # We proceed; the agent might fail the 'add channel' step if it doesn't exist, 
    # but the environment should handle seeding.
  fi

else
  echo "WARNING: Could not authenticate to check initial state. Assuming clean state."
fi

# Launch Firefox on Rocket.Chat login page
echo "Launching Firefox..."
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="