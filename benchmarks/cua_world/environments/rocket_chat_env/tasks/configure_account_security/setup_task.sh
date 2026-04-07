#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_account_security task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
rm -f /tmp/task_start.png 2>/dev/null || true

# Wait for Rocket.Chat API to become reachable
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

# Establish initial clean/insecure state using REST API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Helper to update settings
  update_setting() {
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"value\": $2}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/settings/$1" >/dev/null 2>&1 || true
  }

  echo "Resetting Account security settings to weak defaults..."
  update_setting "Accounts_LoginExpiration" "30"
  update_setting "Accounts_Password_Policy_Enabled" "false"
  update_setting "Accounts_Password_Policy_MinLength" "6"
  update_setting "Accounts_Password_Policy_AtLeastOneLowercase" "false"
  update_setting "Accounts_Password_Policy_AtLeastOneUppercase" "false"
  update_setting "Accounts_Password_Policy_AtLeastOneNumber" "false"
  update_setting "Accounts_Password_Policy_AtLeastOneSymbol" "false"
  update_setting "Accounts_Password_Policy_ForbidRepeatingCharacters" "false"
  update_setting "Accounts_Password_Policy_MaxRepeatingCharacters" "0"
  update_setting "Accounts_Password_History_Enabled" "false"
  update_setting "Accounts_Password_History_Amount" "1"
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