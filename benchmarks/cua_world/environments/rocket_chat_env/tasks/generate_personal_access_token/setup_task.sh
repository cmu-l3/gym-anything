#!/bin/bash
set -euo pipefail

echo "=== Setting up Generate Personal Access Token task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt
# Also in ISO format for easier debugging/comparisons if needed
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_iso.txt

# 2. Ensure Rocket.Chat is healthy
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# 3. Clean up existing token if it exists (to ensure clean state)
echo "Cleaning up any existing 'gitlab-ci' tokens..."

# Login as admin to use API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
    # List tokens
    TOKENS_JSON=$(curl -sS -X GET \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.getPersonalAccessTokens" 2>/dev/null || true)
    
    # Check if 'gitlab-ci' exists
    TOKEN_NAME="gitlab-ci"
    # Note: jq filter returns the name if found
    TOKEN_EXISTS=$(echo "$TOKENS_JSON" | jq -r --arg name "$TOKEN_NAME" '.tokens[]? | select(.name == $name) | .name' 2>/dev/null || true)
    
    if [ "$TOKEN_EXISTS" == "$TOKEN_NAME" ]; then
        echo "Found existing token '$TOKEN_NAME', removing..."
        curl -sS -X POST \
            -H "X-Auth-Token: $AUTH_TOKEN" \
            -H "X-User-Id: $USER_ID" \
            -H "Content-Type: application/json" \
            -d "{\"tokenName\":\"$TOKEN_NAME\"}" \
            "${ROCKETCHAT_BASE_URL}/api/v1/users.removePersonalAccessToken" >/dev/null 2>&1 || true
    fi
else
    echo "WARNING: Could not login to clean up tokens. This might be fine if the server is just starting."
fi

# 4. Remove output file if it exists
rm -f /home/ga/gitlab_token.txt

# 5. Start Firefox at Login Page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Ensure window is focused and ready
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="