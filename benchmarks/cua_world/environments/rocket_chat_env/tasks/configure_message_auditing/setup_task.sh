#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_message_auditing task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# 3. Ensure API access
echo "Verifying admin API access..."
for _ in {1..30}; do
  if api_login "admin" "Admin1234!"; then
    break
  fi
  sleep 2
done

if ! api_login "admin" "Admin1234!"; then
  echo "ERROR: Could not log in to API"
  exit 1
fi

# Extract token/userid from api_login response (saved in $response by task_utils)
AUTH_TOKEN=$(echo "$response" | jq -r '.data.authToken')
USER_ID=$(echo "$response" | jq -r '.data.userId')

# 4. Reset settings to known defaults (Bad state) to ensure task is performable
echo "Resetting message settings to defaults..."
# Defaults: ReadReceipt=False, Edit=True, BlockEdit=0, Delete=True

update_setting() {
  local key="$1"
  local value="$2"
  curl -s -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"value\": $value}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" >/dev/null
}

update_setting "Message_Read_Receipt_Enabled" "false"
update_setting "Message_AllowEditing" "true"
update_setting "Message_AllowEditing_BlockEditInMinutes" "0"
update_setting "Message_AllowDeleting" "true"

# 5. Record initial state for anti-gaming
echo "Recording initial state..."
cat > /tmp/initial_settings_state.json << EOF
{
  "Message_Read_Receipt_Enabled": false,
  "Message_AllowEditing": true,
  "Message_AllowEditing_BlockEditInMinutes": 0,
  "Message_AllowDeleting": true
}
EOF

# 6. Prepare Browser
# Start at login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="