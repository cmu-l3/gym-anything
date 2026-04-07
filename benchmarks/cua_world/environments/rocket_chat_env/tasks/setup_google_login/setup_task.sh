#!/bin/bash
set -euo pipefail

echo "=== Setting up setup_google_login task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# 3. Authenticate as Admin to prepare state
echo "Authenticating as admin to reset OAuth settings..."
RETRIES=30
for i in $(seq 1 $RETRIES); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    echo "Login successful"
    break
  fi
  sleep 2
  if [ "$i" -eq "$RETRIES" ]; then
    echo "ERROR: Failed to login to prepare task"
    exit 1
  fi
done

# 4. Reset Google OAuth settings to ensure clean state (Disabled/Empty)
# We use curl directly here since api_login sets up the session but we need specific headers for the post
# Actually, the api_login function in task_utils checks validity but doesn't export the token for subsequent curl calls easily
# Re-authenticating to get token for cleanup
LOGIN_JSON=$(curl -s -X POST "${ROCKETCHAT_BASE_URL}/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"user\": \"$ROCKETCHAT_TASK_USERNAME\", \"password\": \"$ROCKETCHAT_TASK_PASSWORD\"}")

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "ERROR: Could not get auth token for setup"
    exit 1
fi

update_setting() {
    local key="$1"
    local value="$2"
    echo "Resetting $key..."
    curl -s -X POST "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"value\": $value}" > /dev/null
}

# Reset settings to known initial state (Disabled, empty strings)
update_setting "Accounts_OAuth_Google" "false"
update_setting "Accounts_OAuth_Google_id" "\"\""
update_setting "Accounts_OAuth_Google_secret" "\"\""

# Record initial values for debugging/verification
echo "Recording initial state..."
curl -s -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_OAuth_Google" > /tmp/initial_setting_enable.json

# 5. Launch Firefox
if ! restart_firefox "${ROCKETCHAT_BASE_URL}/home" 5; then
    echo "ERROR: Failed to start Firefox"
    exit 1
fi

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="