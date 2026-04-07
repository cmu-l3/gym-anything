#!/bin/bash
set -euo pipefail

echo "=== Setting up create_private_channel task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Verify Mattermost API is reachable
if ! wait_for_http "${MATTERMOST_BASE_URL}/api/v4/system/ping" 600; then
  echo "ERROR: Mattermost API is not reachable at ${MATTERMOST_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if mm_api_login "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! mm_api_login "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# Ensure the 'incident-response' channel does NOT exist (clean state)
echo "Ensuring incident-response channel does not exist..."
AUTH_TOKEN=$(mm_get_auth_token "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD" || true)

if [ -n "$AUTH_TOKEN" ]; then
  TEAM_INFO=$(curl -sS \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    "${MATTERMOST_BASE_URL}/api/v4/teams/name/main-team" 2>/dev/null || true)
  TEAM_ID=$(echo "$TEAM_INFO" | jq -r '.id // empty' 2>/dev/null || true)

  if [ -n "$TEAM_ID" ]; then
    # Try to find and delete the channel if it exists
    CHANNEL_INFO=$(curl -sS \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      "${MATTERMOST_BASE_URL}/api/v4/teams/${TEAM_ID}/channels/name/incident-response" 2>/dev/null || true)
    CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.id // empty' 2>/dev/null || true)

    if [ -n "$CHANNEL_ID" ]; then
      curl -sS -X DELETE \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        "${MATTERMOST_BASE_URL}/api/v4/channels/${CHANNEL_ID}" >/dev/null 2>&1 || true
      echo "Deleted existing incident-response channel."

      # Permanently delete it
      curl -sS -X POST \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        "${MATTERMOST_BASE_URL}/api/v4/channels/${CHANNEL_ID}/permanent_delete" >/dev/null 2>&1 || true
    else
      echo "incident-response channel does not exist (good)."
    fi
  fi
fi

# Start Firefox at Mattermost login page
if ! restart_firefox "$MATTERMOST_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$MATTERMOST_LOGIN_URL"
sleep 2
focus_firefox || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
