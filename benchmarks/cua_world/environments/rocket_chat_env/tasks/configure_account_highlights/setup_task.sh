#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_account_highlights task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Ensure admin user can log in via API
echo "Verifying admin API access..."
for _ in {1..30}; do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    echo "API login successful"
    break
  fi
  sleep 2
done

# RESET STATE: Clear any existing highlight words for the admin user
# We need the Auth Token and User ID to make authorized calls
LOGIN_JSON=$(curl -s -X POST \
    -H "Content-type: application/json" \
    -d "{\"user\": \"$ROCKETCHAT_TASK_USERNAME\", \"password\": \"$ROCKETCHAT_TASK_PASSWORD\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/login")

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId')

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo "Clearing existing highlight words..."
    # API endpoint to save preferences
    # Note: The exact key for highlights in preferences payload might vary by version,
    # but 'highlights' is standard. We send an empty array or string.
    curl -s -X POST \
        -H "X-Auth-Token: $TOKEN" \
        -H "X-User-Id: $USER_ID" \
        -H "Content-type: application/json" \
        -d '{"data": {"highlights": []}}' \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.saveUserPreferences" > /dev/null
else
    echo "WARNING: Failed to get auth token. Setup might be incomplete."
fi

# Start Firefox
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Navigate to login page and focus
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="